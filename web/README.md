# flowstate invite pages

Live at **https://flowstate.lukakaroli.si** (CNAME at freedns.si → Vercel, project root `web`).

The page an invite link opens (`/join/CODE`) and the file that lets those links open the app directly (Universal Links). It's static: no build step.

## Deploy on Vercel (free)

1. Go to vercel.com and choose **Add New → Project**. Import the flowstate GitHub repo.
2. Set **Root Directory** to `web`. Leave the framework as **Other**, then **Deploy**.
3. Under **Settings → Domains**, rename the domain to something like `flowstate-groups.vercel.app`.
4. Check that `https://<your-domain>/.well-known/apple-app-site-association` shows the JSON.
5. Put that domain in `InviteLink.webHost` in the app, and add it as an Associated Domain (`applinks:<your-domain>`).

## Before sharing widely

- **Get flowstate link:** in `join.html`, replace `GET_APP_URL` with the public TestFlight link (later, the App Store link).
- **Own domain later:** a domain you own works the same way. Add it in Vercel, then repeat step 5. Old `vercel.app` links keep working as long as the project stays up.
