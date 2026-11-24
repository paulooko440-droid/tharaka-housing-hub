# Tharaka University Housing Hub

A responsive student-accommodation website for rooms and hostels around Tharaka University and Marimanti.

## Files
- `index.html`: website frontend
- `supabase-schema.sql`: database tables, security policies and photo storage policies

## Setup before launch
1. Create a free project at https://supabase.com/.
2. In Supabase Project Settings → API, copy the Project URL and publishable/anon key.
3. Edit `index.html`: replace `YOUR_SUPABASE_URL` and `YOUR_SUPABASE_ANON_KEY`. Never place a service-role key in browser code.
4. In Supabase SQL Editor, run all of `supabase-schema.sql`.
5. Create an account on the site. In Supabase SQL Editor, promote your account to administrator by running this after replacing the email:
   ```sql
   update public.profiles set role='admin'
   where id=(select id from auth.users where email='YOUR_ADMIN_EMAIL');
   ```
6. Configure Supabase Auth allowed redirect URLs to include your published GitHub Pages URL.

## Publish with GitHub Pages
Open repository Settings → Pages → Build and deployment → Deploy from a branch. Select `main` and `/(root)`, then Save. Wait for the URL to appear.

## Important
- Until Supabase is configured, the site displays one clearly labelled sample preview listing. It is not a real room.
- Do not publish fake landlord contacts or properties. Obtain permission before posting phone numbers and photos.
- Test sign-up, listing submission, admin approval, photo upload and mobile layout before public launch.
- Favourites, maps, reviews, booking payments, SMS and user suspension are not implemented in this starter.
- Verify all row-level security policies and your operational process before handling real users or deposits.
