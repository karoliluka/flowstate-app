-- flowstate study groups: accounts, groups, invites, weekly leaderboard and "focusing now".
-- Run once in Supabase → SQL Editor (safe to run again: it only creates what's missing
-- and replaces functions and policies).
--
-- What leaves the phone: first and last name, total focus time, this week's focus time,
-- and when the current session started. Never subjects, session details or app choices.

-- ───────────────────────── Tables ─────────────────────────

create table if not exists public.profiles (
    id            uuid primary key references auth.users on delete cascade,
    first_name    text not null default '' check (char_length(first_name) <= 40),
    last_name     text not null default '' check (char_length(last_name) <= 40),
    -- All-time focus, in seconds. Reported by the app from the sessions on the phone.
    total_seconds bigint not null default 0 check (total_seconds >= 0),
    -- Focus in the ISO week (Monday to Sunday) starting on week_start.
    week_start    date,
    week_seconds  bigint not null default 0 check (week_seconds >= 0),
    -- Set while a focus session runs, null otherwise.
    active_since  timestamptz,
    updated_at    timestamptz not null default now()
);

create table if not exists public.groups (
    id          uuid primary key default gen_random_uuid(),
    name        text not null check (char_length(btrim(name)) between 1 and 40),
    -- Kept when the owner deletes their account, so the group lives on for everyone else.
    owner_id    uuid references auth.users on delete set null,
    invite_code text not null unique default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
    created_at  timestamptz not null default now()
);

create table if not exists public.group_members (
    group_id  uuid not null references public.groups on delete cascade,
    user_id   uuid not null references auth.users on delete cascade,
    joined_at timestamptz not null default now(),
    primary key (group_id, user_id)
);

create index if not exists group_members_user_idx on public.group_members (user_id);

-- ───────────────────────── Helpers ─────────────────────────
-- security definer so policies can ask "is this person in my group?" without
-- the policies on group_members recursing into themselves.

create or replace function public.is_group_member(target_group uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (select 1 from group_members where group_id = target_group and user_id = auth.uid());
$$;

create or replace function public.shares_group_with(other_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from group_members mine
        join group_members theirs on theirs.group_id = mine.group_id
        where mine.user_id = auth.uid() and theirs.user_id = other_user
    );
$$;

-- A profile for every new account, with the name given at sign-up (email, Google) if any.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
    insert into profiles (id, first_name, last_name)
    values (
        new.id,
        left(coalesce(new.raw_user_meta_data->>'first_name', new.raw_user_meta_data->>'given_name',
                      split_part(coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', ''), ' ', 1), ''), 40),
        left(coalesce(new.raw_user_meta_data->>'last_name', new.raw_user_meta_data->>'family_name', ''), 40)
    )
    on conflict (id) do nothing;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
    for each row execute function public.handle_new_user();

-- ───────────────────────── Row level security ─────────────────────────

alter table public.profiles enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;

drop policy if exists "profiles: read own and group mates" on public.profiles;
create policy "profiles: read own and group mates" on public.profiles for select to authenticated
    using (id = auth.uid() or public.shares_group_with(id));

drop policy if exists "profiles: update own" on public.profiles;
create policy "profiles: update own" on public.profiles for update to authenticated
    using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "profiles: insert own" on public.profiles;
create policy "profiles: insert own" on public.profiles for insert to authenticated
    with check (id = auth.uid());

drop policy if exists "groups: members read" on public.groups;
create policy "groups: members read" on public.groups for select to authenticated
    using (public.is_group_member(id));

drop policy if exists "groups: owner renames" on public.groups;
create policy "groups: owner renames" on public.groups for update to authenticated
    using (owner_id = auth.uid()) with check (owner_id = auth.uid());

drop policy if exists "groups: owner deletes" on public.groups;
create policy "groups: owner deletes" on public.groups for delete to authenticated
    using (owner_id = auth.uid());

drop policy if exists "members: read own groups" on public.group_members;
create policy "members: read own groups" on public.group_members for select to authenticated
    using (public.is_group_member(group_id));

drop policy if exists "members: leave" on public.group_members;
create policy "members: leave" on public.group_members for delete to authenticated
    using (user_id = auth.uid());

-- Groups are created and joined only through the functions below.

-- ───────────────────────── Functions the app calls ─────────────────────────

create or replace function public.create_group(group_name text)
returns public.groups language plpgsql security definer set search_path = public as $$
declare
    created groups;
begin
    if auth.uid() is null then raise exception 'not signed in'; end if;
    insert into groups (name, owner_id) values (btrim(group_name), auth.uid()) returning * into created;
    insert into group_members (group_id, user_id) values (created.id, auth.uid());
    return created;
end;
$$;

create or replace function public.join_group(code text)
returns public.groups language plpgsql security definer set search_path = public as $$
declare
    found groups;
begin
    if auth.uid() is null then raise exception 'not signed in'; end if;
    select * into found from groups where invite_code = upper(btrim(code));
    if found.id is null then raise exception 'invite not found'; end if;
    insert into group_members (group_id, user_id) values (found.id, auth.uid()) on conflict do nothing;
    return found;
end;
$$;

-- What an invite link shows before joining, also on the web page (so anyone with the code may ask).
create or replace function public.group_preview(code text)
returns table (group_name text, owner_first_name text, member_count bigint)
language sql stable security definer set search_path = public as $$
    select g.name, coalesce(p.first_name, ''), (select count(*) from group_members m where m.group_id = g.id)
    from groups g left join profiles p on p.id = g.owner_id
    where g.invite_code = upper(btrim(code));
$$;

-- Deletes the signed-in account and everything tied to it (profile, memberships).
-- Groups they own stay for the other members.
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public as $$
begin
    if auth.uid() is null then raise exception 'not signed in'; end if;
    delete from auth.users where id = auth.uid();
end;
$$;

revoke all on function public.create_group(text), public.join_group(text), public.delete_my_account() from public, anon;
grant execute on function public.create_group(text), public.join_group(text), public.delete_my_account() to authenticated;
grant execute on function public.group_preview(text) to anon, authenticated;
