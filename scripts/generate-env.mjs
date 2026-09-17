import { writeFileSync } from 'node:fs'

const value = (name, fallback = '') => String(process.env[name] || fallback).trim()
const url = value('SUPABASE_URL')
const anonKey = value('SUPABASE_PUBLISHABLE_KEY', value('SUPABASE_ANON_KEY'))
const vapidPublicKey = value('VAPID_PUBLIC_KEY')

const output = `window.TRIPSYNC_ENV = ${JSON.stringify({ url, anonKey, vapidPublicKey }, null, 2)};\n`
writeFileSync('env.js', output, 'utf8')
console.log(`TripSync environment file generated (${url ? 'backend configured' : 'backend not configured'}).`)
