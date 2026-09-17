import { createClient } from "npm:@supabase/supabase-js@2"
import webpush from "npm:web-push@3.6.7"

const supabaseUrl = Deno.env.get("SUPABASE_URL") || ""
const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || ""
const vapidPublicKey = Deno.env.get("VAPID_PUBLIC_KEY") || ""
const vapidPrivateKey = Deno.env.get("VAPID_PRIVATE_KEY") || ""
const vapidEmail = Deno.env.get("VAPID_EMAIL") || "mailto:admin@example.com"
const siteUrl = (Deno.env.get("SITE_URL") || "").replace(/\/$/, "")
const webhookSecret = Deno.env.get("PUSH_WEBHOOK_SECRET") || ""

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } })

if (!supabaseUrl || !serviceRole || !vapidPublicKey || !vapidPrivateKey || !siteUrl) {
  console.error("Push sender is not configured")
}

const supabase = createClient(supabaseUrl, serviceRole)
webpush.setVapidDetails(vapidEmail, vapidPublicKey, vapidPrivateKey)

const labels: Record<string, string> = {
  itinerary_items: "itinerary",
  suggestions: "suggestions",
  polls: "decisions",
  poll_votes: "decisions",
  posts: "board",
  post_replies: "board",
  trip_links: "links",
  checklist_items: "checklist",
  checklist_checks: "checklist",
  expenses: "money",
  expense_shares: "money",
  settlements: "settlements",
  trip_members: "crew"
}

Deno.serve(async req => {
  try {
    if (webhookSecret && req.headers.get("x-tripsync-webhook-secret") !== webhookSecret) {
      return json({ error: "Unauthorized" }, 401)
    }

    const payload = await req.json()
    const record = payload?.record || {}
    const table = String(payload?.table || "")
    const tripId = record.trip_id
    if (!tripId) return json({ ignored: true })

    const actor = record.created_by || record.user_id || record.paid_by || null
    const { data: trip, error: tripError } = await supabase
      .from("trips").select("id,name").eq("id", tripId).maybeSingle()
    if (tripError || !trip) return json({ ignored: true })

    const { data: members } = await supabase
      .from("trip_members").select("user_id").eq("trip_id", tripId)
    const recipients = (members || []).map(m => m.user_id).filter(id => id !== actor)
    if (!recipients.length) return json({ sent: 0 })

    const { data: prefs } = await supabase
      .from("trip_alert_preferences")
      .select("user_id,enabled")
      .eq("trip_id", tripId)
      .in("user_id", recipients)
    const disabled = new Set((prefs || []).filter(p => p.enabled === false).map(p => p.user_id))
    const enabledRecipients = recipients.filter(id => !disabled.has(id))
    if (!enabledRecipients.length) return json({ sent: 0 })

    const { data: subs } = await supabase
      .from("push_subscriptions")
      .select("user_id,endpoint,p256dh,auth")
      .in("user_id", enabledRecipients)
    if (!subs?.length) return json({ sent: 0 })

    const area = labels[table] || "trip"
    const description = String(record.title || record.description || record.body ||
      (table === "trip_members" ? "A new member joined the trip." : `New activity in ${area}.`))

    let sent = 0
    for (const sub of subs) {
      try {
        await webpush.sendNotification(
          { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
          JSON.stringify({
            title: trip.name || "TripSync",
            body: `${description} · ${area}`,
            tag: `${tripId}-${area}`,
            url: `${siteUrl}/#/trip/${tripId}`
          })
        )
        sent++
      } catch (error) {
        const status = (error as any)?.statusCode
        if (status === 404 || status === 410) {
          await supabase.from("push_subscriptions").delete().eq("endpoint", sub.endpoint)
        }
      }
    }

    return json({ sent })
  } catch (error) {
    console.error(error)
    return json({ error: "Push notification delivery failed" }, 500)
  }
})
