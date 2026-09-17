# TripSync notifications

## Frontend / Netlify
Set these Netlify environment variables:
- SUPABASE_URL
- SUPABASE_PUBLISHABLE_KEY
- VAPID_PUBLIC_KEY

The build creates `env.js`. `env.js` is ignored by Git because it contains public configuration generated at deploy time.

## VAPID keys
Generate one VAPID key pair. Put the public key in Netlify as `VAPID_PUBLIC_KEY` and the private key only in Supabase Edge Function secrets.

## Supabase Edge Function
Deploy `supabase/functions/send-push/index.ts` as `send-push`.

Set Edge Function secrets:
- SUPABASE_URL (usually already available)
- SUPABASE_SERVICE_ROLE_KEY (usually already available)
- VAPID_PUBLIC_KEY
- VAPID_PRIVATE_KEY
- VAPID_EMAIL
- SITE_URL
- PUSH_WEBHOOK_SECRET

## Database webhooks
Create Database Webhooks in Supabase for the INSERT events you want to notify:
- itinerary_items
- suggestions
- polls
- posts
- post_replies
- trip_links
- checklist_items
- expenses
- settlements
- trip_members

Point them at the `send-push` Edge Function and add header:
`x-tripsync-webhook-secret: <same PUSH_WEBHOOK_SECRET>`

## Browser
Serve TripSync over HTTPS. Sign in, open Crew → Alerts, enable notifications, and allow the browser permission prompt.
