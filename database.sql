-- ============================================================================

-- Revision 2026-09-16h  (run this whole file, top to bottom, not a selection)

-- TripSync — complete database schema for Supabase (Postgres)

-- Run top-to-bottom in Supabase Studio → SQL Editor. Safe to re-run.

-- ============================================================================


 

do $$ begin raise notice 'TripSync schema revision 2026-09-16h'; end $$;


 

create extension if not exists pgcrypto;


 

-- ---------------------------------------------------------------------------

-- 1. Core tables

-- ---------------------------------------------------------------------------


 

create table if not exists public.profiles (

  id          uuid primary key references auth.users on delete cascade,

  full_name   text not null default '',

  phone       text default '',

  created_at  timestamptz not null default now()

);


 

create table if not exists public.trips (

  id          uuid primary key default gen_random_uuid(),

  code        text unique not null,

  name        text not null,

  destination text not null default '',

  start_date  date,

  end_date    date,

  budget      numeric(12,2) not null default 0,

  currency    text not null default 'INR',

  status      text not null default 'planning',  -- planning | live | done

  notes       text default '',

  created_by  uuid not null references auth.users on delete cascade,

  created_at  timestamptz not null default now()

);


 

-- user_id points at profiles (not auth.users) so PostgREST can embed member

-- names in one query: trip_members → profiles.

create table if not exists public.trip_members (

  trip_id   uuid not null references public.trips on delete cascade,

  user_id   uuid not null references public.profiles(id) on delete cascade,

  role      text not null default 'member',      -- admin | member

                                                  -- (trips.created_by records

                                                  --  who started it; it grants

                                                  --  no extra rights)

  budget    numeric(12,2) not null default 0,     -- this member's own budget

  seen      jsonb not null default '{}'::jsonb,  -- area -> last read, drives badges

  joined_at timestamptz not null default now(),

  primary key (trip_id, user_id)

);


 

-- Itinerary -----------------------------------------------------------------

create table if not exists public.itinerary_items (

  id          uuid primary key default gen_random_uuid(),

  trip_id     uuid not null references public.trips on delete cascade,

  title       text not null,

  description text default '',

  location    text default '',

  start_time  timestamptz not null,

  end_time    timestamptz,

  category    text default 'activity',           -- travel | stay | activity | food

  completed_at timestamptz,                       -- set when the group ticks it off

  completed_by uuid references public.profiles(id) on delete set null,

  created_by  uuid not null references auth.users on delete cascade,

  created_at  timestamptz not null default now()

);


 

-- A suggestion always belongs to a stop, and carries no status of its own:

-- the verdict is whatever the group voted, so one person accepting out of five

-- never decides anything.

create table if not exists public.suggestions (

  id          uuid primary key default gen_random_uuid(),

  trip_id     uuid not null references public.trips on delete cascade,

  item_id     uuid not null references public.itinerary_items on delete cascade,

  body        text not null,

  created_by  uuid not null references auth.users on delete cascade,

  created_at  timestamptz not null default now()

);


 

create table if not exists public.suggestion_votes (

  trip_id       uuid not null references public.trips on delete cascade,

  suggestion_id uuid not null references public.suggestions on delete cascade,

  user_id       uuid not null references public.profiles(id) on delete cascade,

  vote          text not null check (vote in ('accept', 'decline')),

  voted_at      timestamptz not null default now(),

  primary key (suggestion_id, user_id)

);


 

create table if not exists public.attendance (

  trip_id    uuid not null references public.trips on delete cascade,

  item_id    uuid not null references public.itinerary_items on delete cascade,

  user_id    uuid not null references auth.users on delete cascade,

  status     text not null default 'in',         -- in | maybe | out

  updated_at timestamptz not null default now(),

  primary key (item_id, user_id)

);


 

-- Decisions & comms ---------------------------------------------------------

create table if not exists public.polls (

  id         uuid primary key default gen_random_uuid(),

  trip_id    uuid not null references public.trips on delete cascade,

  question   text not null,

  options    jsonb not null default '[]'::jsonb, -- ["Beach","Fort"]

  closed     boolean not null default false,

  show_voters boolean not null default true,      -- false hides who voted for what

  allow_multiple boolean not null default false,   -- true lets each person choose multiple options

  created_by uuid not null references auth.users on delete cascade,

  created_at timestamptz not null default now()

);


 

create table if not exists public.poll_votes (

  poll_id      uuid not null references public.polls on delete cascade,

  user_id      uuid not null references auth.users on delete cascade,

  option_index int not null,

  voted_at     timestamptz not null default now(),

  primary key (poll_id, user_id, option_index)

);


 

-- THE BOARD — one feed, two kinds of post.

--

-- A notice is something the group must read; a question also collects replies

-- and tracks who has not answered yet. Both accept replies, so a notice can be

-- discussed without needing a second mechanism. headcount is the number of

-- members when a question was asked, minus nothing — the asker is excluded in

-- the reading, not here — so a later joiner cannot un-pack a finished round.

create table if not exists public.posts (

  id         uuid primary key default gen_random_uuid(),

  trip_id    uuid not null references public.trips on delete cascade,

  kind       text not null default 'notice' check (kind in ('notice', 'question')),

  title      text default '',

  body       text not null,

  pinned     boolean not null default false,

  state      text not null default 'ok',        -- ok | delayed | arrived | help

  headcount  int not null default 1 check (headcount > 0),

  closed_at  timestamptz,                       -- a question wrapped early

  closed_by  uuid references public.profiles(id) on delete set null,

  created_by uuid not null references public.profiles(id) on delete cascade,

  created_at timestamptz not null default now()

);


 

create table if not exists public.post_replies (

  id         uuid primary key default gen_random_uuid(),

  trip_id    uuid not null references public.trips on delete cascade,

  post_id    uuid not null references public.posts on delete cascade,

  user_id    uuid not null references public.profiles(id) on delete cascade,

  body       text not null,

  created_at timestamptz not null default now()

);


 

-- Somewhere to drop a shared album or folder link.

create table if not exists public.trip_links (

  id         uuid primary key default gen_random_uuid(),

  trip_id    uuid not null references public.trips on delete cascade,

  title      text not null,

  url        text not null,

  created_by uuid not null references public.profiles(id) on delete cascade,

  created_at timestamptz not null default now()

);


 

-- A shared reference list: anyone adds, everyone sees. Ticking is personal,

-- so one member checking something off does not clear it for the others.

create table if not exists public.checklist_items (

  id          uuid primary key default gen_random_uuid(),

  trip_id     uuid not null references public.trips on delete cascade,

  title       text not null,

  is_private  boolean not null default false,    -- true: only its author sees it

  created_by  uuid not null references auth.users on delete cascade,

  created_at  timestamptz not null default now()

);


 

create table if not exists public.checklist_checks (

  trip_id    uuid not null references public.trips on delete cascade,

  item_id    uuid not null references public.checklist_items on delete cascade,

  user_id    uuid not null references public.profiles(id) on delete cascade,

  checked_at timestamptz not null default now(),

  primary key (item_id, user_id)

);


 

-- for_user is whose contact this is; null means it serves the whole trip

-- (hotel desk, local hospital).

create table if not exists public.emergency_contacts (

  id         uuid primary key default gen_random_uuid(),

  trip_id    uuid not null references public.trips on delete cascade,

  for_user   uuid references public.profiles(id) on delete cascade,

  name       text not null,

  relation   text default '',

  phone      text not null,

  notes      text default '',

  created_by uuid not null references auth.users on delete cascade,

  created_at timestamptz not null default now()

);


 

-- Money ---------------------------------------------------------------------

create table if not exists public.budget_lines (

  id       uuid primary key default gen_random_uuid(),

  trip_id  uuid not null references public.trips on delete cascade,

  user_id  uuid not null references public.profiles(id) on delete cascade,

  category text not null,

  planned  numeric(12,2) not null default 0,

  created_at timestamptz not null default now(),

  unique (trip_id, user_id, category)

);


 

create table if not exists public.expenses (

  id          uuid primary key default gen_random_uuid(),

  trip_id     uuid not null references public.trips on delete cascade,

  description text not null,

  amount      numeric(12,2) not null check (amount > 0),

  category    text not null default 'Other',

  paid_by     uuid not null references auth.users on delete cascade,

  spent_on    date not null default current_date,

  created_by  uuid not null references auth.users on delete cascade,

  created_at  timestamptz not null default now()

);


 

create table if not exists public.expense_shares (

  expense_id uuid not null references public.expenses on delete cascade,

  user_id    uuid not null references auth.users on delete cascade,

  amount     numeric(12,2) not null default 0,

  primary key (expense_id, user_id)

);


 

create table if not exists public.settlements (

  id         uuid primary key default gen_random_uuid(),

  trip_id    uuid not null references public.trips on delete cascade,

  from_user  uuid not null references auth.users on delete cascade,

  to_user    uuid not null references auth.users on delete cascade,

  amount     numeric(12,2) not null check (amount > 0),

  note       text default '',

  created_by uuid not null references auth.users on delete cascade,

  created_at timestamptz not null default now()

);


 

-- Optional location sharing (row exists only while a member opts in) --------

create table if not exists public.member_locations (

  trip_id    uuid not null references public.trips on delete cascade,

  user_id    uuid not null references auth.users on delete cascade,

  lat        double precision not null,

  lng        double precision not null,

  accuracy   double precision,

  label      text default '',

  updated_at timestamptz not null default now(),

  primary key (trip_id, user_id)

);


 

create index if not exists idx_members_user on public.trip_members(user_id);

create index if not exists idx_itinerary_trip on public.itinerary_items(trip_id, start_time);

create index if not exists idx_expenses_trip on public.expenses(trip_id, spent_on desc);

create index if not exists idx_checks_trip on public.checklist_checks(trip_id, user_id);

create index if not exists idx_sugvotes_trip on public.suggestion_votes(trip_id, suggestion_id);

-- Every list in the app filters by trip_id, so each trip-scoped table gets one.

create index if not exists idx_suggestions_trip on public.suggestions(trip_id);

create index if not exists idx_attendance_trip on public.attendance(trip_id);

create index if not exists idx_attendance_user on public.attendance(user_id);

create index if not exists idx_polls_trip on public.polls(trip_id);

create index if not exists idx_checklist_trip on public.checklist_items(trip_id);

create index if not exists idx_checks_user on public.checklist_checks(user_id);

create index if not exists idx_contacts_trip on public.emergency_contacts(trip_id);

create index if not exists idx_settlements_trip on public.settlements(trip_id);

create index if not exists idx_links_trip on public.trip_links(trip_id);

create index if not exists idx_locations_user on public.member_locations(user_id);

create index if not exists idx_sugvotes_user on public.suggestion_votes(user_id);

create index if not exists idx_posts_trip on public.posts(trip_id, created_at desc);

create index if not exists idx_replies_post on public.post_replies(post_id, created_at);

create index if not exists idx_budget_user on public.budget_lines(trip_id, user_id);


 

-- ---------------------------------------------------------------------------

-- 2. Helpers (security definer → used by policies, so no RLS recursion)

-- ---------------------------------------------------------------------------


 

create or replace function public.is_trip_member(p_trip uuid)

returns boolean language sql stable security definer set search_path = public as $$

  select exists (

    select 1 from public.trip_members m

    where m.trip_id = p_trip and m.user_id = auth.uid()

  );

$$;


 

-- An admin can do everything on a trip. 'owner' is still accepted so a

-- database mid-upgrade keeps working, but nothing writes it any more.

create or replace function public.is_trip_admin(p_trip uuid)

returns boolean language sql stable security definer set search_path = public as $$

  select exists (

    select 1 from public.trip_members m

    where m.trip_id = p_trip and m.user_id = auth.uid() and m.role in ('admin', 'owner')

  );

$$;


 

create or replace function public.shares_trip(p_user uuid)

returns boolean language sql stable security definer set search_path = public as $$

  select exists (

    select 1

    from public.trip_members a

    join public.trip_members b on a.trip_id = b.trip_id

    where a.user_id = auth.uid() and b.user_id = p_user

  );

$$;


 

-- New signups get a profile row automatically.

create or replace function public.handle_new_user()

returns trigger language plpgsql security definer set search_path = public as $$

begin

  insert into public.profiles (id, full_name, phone)

  values (

    new.id,

    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),

    coalesce(new.raw_user_meta_data->>'phone', '')

  )

  on conflict (id) do nothing;

  return new;

end $$;


 

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created

  after insert on auth.users

  for each row execute function public.handle_new_user();


 

-- Anyone who signed up before this script ran still needs a profile row.

insert into public.profiles (id, full_name, phone)

select u.id,

       coalesce(u.raw_user_meta_data->>'full_name', split_part(u.email, '@', 1)),

       coalesce(u.raw_user_meta_data->>'phone', '')

from auth.users u

on conflict (id) do nothing;


 

-- ---------------------------------------------------------------------------

-- 3. RPCs

-- ---------------------------------------------------------------------------


 

-- Create a trip and enrol the creator as owner, atomically.

create or replace function public.create_trip(

  p_name text, p_destination text, p_start date, p_end date,

  p_budget numeric default 0, p_currency text default 'INR'

) returns public.trips language plpgsql security definer set search_path = public as $$

declare t public.trips; c text;

begin

  if auth.uid() is null then raise exception 'Sign in to create a trip'; end if;

  if coalesce(trim(p_name), '') = '' then raise exception 'Trip needs a name'; end if;


 

  loop

    c := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));

    exit when not exists (select 1 from public.trips where code = c);

  end loop;


 

  insert into public.trips (code, name, destination, start_date, end_date, budget, currency, created_by)

  values (c, trim(p_name), coalesce(p_destination, ''), p_start, p_end,

          coalesce(p_budget, 0), coalesce(nullif(p_currency, ''), 'INR'), auth.uid())

  returning * into t;


 

  insert into public.trip_members (trip_id, user_id, role)

  values (t.id, auth.uid(), 'admin');


 

  return t;

end $$;


 

-- Join by invite code. Lets a non-member read exactly one trip row.

create or replace function public.join_trip(p_code text)

returns public.trips language plpgsql security definer set search_path = public as $$

declare t public.trips;

begin

  if auth.uid() is null then raise exception 'Sign in to join a trip'; end if;


 

  select * into t from public.trips where code = upper(trim(p_code));

  if t.id is null then raise exception 'No trip with code %', upper(trim(p_code)); end if;


 

  insert into public.trip_members (trip_id, user_id, role)

  values (t.id, auth.uid(), 'member')

  on conflict (trip_id, user_id) do nothing;


 

  return t;

end $$;


 

-- Add an expense plus its per-person shares in one transaction.

-- p_shares: '[{"user_id":"...","amount":250.00}, ...]'

create or replace function public.add_expense(

  p_trip uuid, p_description text, p_amount numeric, p_category text,

  p_paid_by uuid, p_spent_on date, p_shares jsonb

) returns uuid language plpgsql security definer set search_path = public as $$

declare e_id uuid; total numeric;

begin

  if not public.is_trip_member(p_trip) then raise exception 'Not a member of this trip'; end if;

  if coalesce(p_amount, 0) <= 0 then raise exception 'Amount must be greater than zero'; end if;


 

  if p_amount < 0.01 then

    raise exception 'An expense needs to be at least 0.01';

  end if;


 

  -- The payer and everyone sharing must be on the trip, or their part of the

  -- money would never appear in anybody's balance.

  if not exists (

    select 1 from public.trip_members

    where trip_id = p_trip and user_id = p_paid_by

  ) then

    raise exception 'The payer is not a member of this trip';

  end if;


 

  if exists (

    select 1

    from jsonb_array_elements(coalesce(p_shares, '[]'::jsonb)) s

    where not exists (

      select 1 from public.trip_members m

      where m.trip_id = p_trip and m.user_id = (s->>'user_id')::uuid

    )

  ) then

    raise exception 'A share was assigned to somebody who is not on this trip';

  end if;


 

  select coalesce(sum((s->>'amount')::numeric), 0) into total

  from jsonb_array_elements(coalesce(p_shares, '[]'::jsonb)) s;


 

  if abs(total - p_amount) > 0.05 then

    raise exception 'Shares add up to % but the expense is %', total, p_amount;

  end if;


 

  insert into public.expenses (trip_id, description, amount, category, paid_by, spent_on, created_by)

  values (p_trip, p_description, p_amount, coalesce(nullif(p_category, ''), 'Other'),

          p_paid_by, coalesce(p_spent_on, current_date), auth.uid())

  returning id into e_id;


 

  insert into public.expense_shares (expense_id, user_id, amount)

  select e_id, (s->>'user_id')::uuid, (s->>'amount')::numeric

  from jsonb_array_elements(p_shares) s

  where (s->>'amount')::numeric > 0;


 

  return e_id;

end $$;


 

-- Promote or demote a member. Only an admin may call it, and a trip can never

-- be left without one.

create or replace function public.set_member_role(p_trip uuid, p_user uuid, p_role text)

returns void language plpgsql security definer set search_path = public as $$

begin

  if not public.is_trip_admin(p_trip) then

    raise exception 'Only an admin can change who has rights';

  end if;

  if p_role not in ('admin', 'member') then

    raise exception 'Unknown role %', p_role;

  end if;


 

  update public.trip_members set role = p_role

  where trip_id = p_trip and user_id = p_user;


 

  if not exists (

    select 1 from public.trip_members

    where trip_id = p_trip and role in ('admin', 'owner')

  ) then

    raise exception 'The trip needs at least one admin';

  end if;

end $$;


 

-- Any member may tick a stop off, or put it back. Editing a stop's details

-- stays with its author (see stop_update), but completing one is something

-- the whole group does, so it goes through here instead.

create or replace function public.complete_stop(p_item uuid, p_done boolean)

returns void language plpgsql security definer set search_path = public as $$

declare t uuid;

begin

  select trip_id into t from public.itinerary_items where id = p_item;

  if t is null or not public.is_trip_member(t) then

    raise exception 'Not a member of this trip';

  end if;

  update public.itinerary_items

  set completed_at = case when p_done then now() else null end,

      completed_by = case when p_done then auth.uid() else null end

  where id = p_item;

end $$;


 

-- Any member may wrap a question round early, or undo it.

create or replace function public.wrap_post(p_post uuid, p_wrapped boolean)

returns void language plpgsql security definer set search_path = public as $$

declare t uuid;

begin

  select trip_id into t from public.posts where id = p_post;

  if t is null or not public.is_trip_member(t) then

    raise exception 'Not a member of this trip';

  end if;

  update public.posts

  set closed_at = case when p_wrapped then now() else null end,

      closed_by = case when p_wrapped then auth.uid() else null end

  where id = p_post;

end $$;


 

-- Mark one area of a trip as read, for the unread badges.

create or replace function public.mark_seen(p_trip uuid, p_area text)

returns void language plpgsql security definer set search_path = public as $$

begin

  if not public.is_trip_member(p_trip) then

    raise exception 'Not a member of this trip';

  end if;

  update public.trip_members

  set seen = coalesce(seen, '{}'::jsonb) || jsonb_build_object(p_area, now())

  where trip_id = p_trip and user_id = auth.uid();

end $$;


 

-- Latest activity per area, so the client can badge tabs in one round trip.

create or replace function public.trip_activity(p_trip uuid)

returns jsonb language sql stable security definer set search_path = public as $$

  select case when public.is_trip_member(p_trip) then jsonb_strip_nulls(jsonb_build_object(

    'plan', (select max(greatest(created_at, coalesce(completed_at, created_at)))

             from public.itinerary_items where trip_id = p_trip),

    'plan_notes', (select max(created_at) from public.suggestions where trip_id = p_trip),

    'polls', (select max(created_at) from public.polls where trip_id = p_trip),

    'board', (select max(created_at) from public.posts where trip_id = p_trip),

    'board_replies', (select max(created_at) from public.post_replies where trip_id = p_trip),

    'list', (select max(created_at) from public.checklist_items

             where trip_id = p_trip and (is_private = false or created_by = auth.uid())),

    'money', (select max(created_at) from public.expenses where trip_id = p_trip),

    'safety', (select max(created_at) from public.emergency_contacts where trip_id = p_trip),

    'crew', (select max(joined_at) from public.trip_members where trip_id = p_trip),

    'links', (select max(created_at) from public.trip_links where trip_id = p_trip)

  )) else '{}'::jsonb end;

$$;


 

-- Leave a trip (also stops location sharing).

create or replace function public.leave_trip(p_trip uuid)

returns void language plpgsql security definer set search_path = public as $$

begin

  delete from public.member_locations where trip_id = p_trip and user_id = auth.uid();

  delete from public.trip_members where trip_id = p_trip and user_id = auth.uid();

end $$;


 

grant execute on function public.create_trip(text, text, date, date, numeric, text) to authenticated;

grant execute on function public.join_trip(text) to authenticated;

grant execute on function public.add_expense(uuid, text, numeric, text, uuid, date, jsonb) to authenticated;

grant execute on function public.leave_trip(uuid) to authenticated;

grant execute on function public.set_member_role(uuid, uuid, text) to authenticated;

grant execute on function public.wrap_post(uuid, boolean) to authenticated;

grant execute on function public.complete_stop(uuid, boolean) to authenticated;

grant execute on function public.mark_seen(uuid, text) to authenticated;

grant execute on function public.trip_activity(uuid) to authenticated;


 

-- ---------------------------------------------------------------------------

-- 4. Row level security

-- ---------------------------------------------------------------------------


 

-- Start the policy section from a clean slate.

--

-- Postgres has no "create policy if not exists", and policies have been

-- renamed between versions of this file (tm_insert became loc_insert, and so

-- on). Dropping every policy on our own tables first makes this section

-- deterministic: it no longer matters which version ran before, or in what

-- order, and it can never fail with 42710. Only tables this file creates are

-- touched — anything else in the schema is left alone.

do $$

declare r record;

begin

  for r in

    select policyname, tablename

    from pg_policies

    where schemaname = 'public'

      and tablename in (

        'profiles','trips','trip_members','itinerary_items','suggestions',

        'suggestion_votes','attendance','polls','poll_votes','posts',

        'post_replies','trip_links','checklist_items','checklist_checks',

        'emergency_contacts','budget_lines','expenses','expense_shares',

        'settlements','member_locations'

      )

  loop

    execute format('drop policy if exists %I on public.%I', r.policyname, r.tablename);

  end loop;

end $$;


 

alter table public.profiles     enable row level security;

alter table public.trips        enable row level security;

alter table public.trip_members enable row level security;


 

drop policy if exists profiles_read on public.profiles;

create policy profiles_read on public.profiles for select to authenticated

  using (id = auth.uid() or public.shares_trip(id));


 

drop policy if exists profiles_write on public.profiles;

create policy profiles_write on public.profiles for update to authenticated

  using (id = auth.uid()) with check (id = auth.uid());


 

drop policy if exists profiles_insert on public.profiles;

create policy profiles_insert on public.profiles for insert to authenticated

  with check (id = auth.uid());


 

drop policy if exists trips_read on public.trips;

create policy trips_read on public.trips for select to authenticated

  using (public.is_trip_member(id));


 

-- The owner and any admin edit or delete the trip itself. Everything inside

-- the trip stays open to every member.

drop policy if exists trips_update on public.trips;

create policy trips_update on public.trips for update to authenticated

  using (public.is_trip_admin(id)) with check (public.is_trip_admin(id));


 

drop policy if exists trips_delete on public.trips;

create policy trips_delete on public.trips for delete to authenticated

  using (public.is_trip_admin(id));


 

drop policy if exists members_read on public.trip_members;

create policy members_read on public.trip_members for select to authenticated

  using (public.is_trip_member(trip_id));


 

drop policy if exists members_leave on public.trip_members;

create policy members_leave on public.trip_members for delete to authenticated

  using (user_id = auth.uid() or public.is_trip_admin(trip_id));


 

-- Every trip-scoped table shares one rule: members of the trip can read and

-- write its rows. Trips are small groups of people who trust each other, so

-- per-row ownership checks would add friction without adding safety.

do $$

declare tbl text;

begin

  foreach tbl in array array[

    'itinerary_items','suggestions','suggestion_votes','attendance','polls',

    'posts','post_replies','trip_links','checklist_items','checklist_checks',

    'emergency_contacts','budget_lines','expenses','settlements','member_locations'

  ] loop

    execute format('alter table public.%I enable row level security', tbl);

    execute format('drop policy if exists tm_read on public.%I', tbl);

    execute format('drop policy if exists tm_insert on public.%I', tbl);

    execute format('drop policy if exists tm_update on public.%I', tbl);

    execute format('drop policy if exists tm_delete on public.%I', tbl);

    execute format('create policy tm_read on public.%I for select to authenticated using (public.is_trip_member(trip_id))', tbl);

    execute format('create policy tm_insert on public.%I for insert to authenticated with check (public.is_trip_member(trip_id))', tbl);

    execute format('create policy tm_update on public.%I for update to authenticated using (public.is_trip_member(trip_id)) with check (public.is_trip_member(trip_id))', tbl);

    execute format('create policy tm_delete on public.%I for delete to authenticated using (public.is_trip_member(trip_id))', tbl);

  end loop;

end $$;


 

-- Children without a trip_id inherit access from their parent row.

alter table public.poll_votes enable row level security;

drop policy if exists votes_read on public.poll_votes;

create policy votes_read on public.poll_votes for select to authenticated

  using (public.is_trip_member((select trip_id from public.polls p where p.id = poll_id)));


 

drop policy if exists votes_write on public.poll_votes;

create policy votes_write on public.poll_votes for all to authenticated

  using (user_id = auth.uid()) with check (

    user_id = auth.uid()

    and public.is_trip_member((select trip_id from public.polls p where p.id = poll_id))

  );


 

alter table public.expense_shares enable row level security;

drop policy if exists shares_read on public.expense_shares;

create policy shares_read on public.expense_shares for select to authenticated

  using (public.is_trip_member((select trip_id from public.expenses e where e.id = expense_id)));


 

drop policy if exists shares_write on public.expense_shares;

create policy shares_write on public.expense_shares for all to authenticated

  using (public.is_trip_member((select trip_id from public.expenses e where e.id = expense_id)))

  with check (public.is_trip_member((select trip_id from public.expenses e where e.id = expense_id)));


 

-- Location rows may only be written by their owner (opt-in, revocable).

drop policy if exists tm_insert on public.member_locations;

drop policy if exists loc_insert on public.member_locations;

create policy loc_insert on public.member_locations for insert to authenticated

  with check (user_id = auth.uid() and public.is_trip_member(trip_id));


 

drop policy if exists tm_update on public.member_locations;

drop policy if exists loc_update on public.member_locations;

create policy loc_update on public.member_locations for update to authenticated

  using (user_id = auth.uid()) with check (user_id = auth.uid());


 

drop policy if exists tm_delete on public.member_locations;

drop policy if exists loc_delete on public.member_locations;

create policy loc_delete on public.member_locations for delete to authenticated

  using (user_id = auth.uid());


 

-- A member may edit their own row (that is where their personal budget lives)

-- but not anyone else's.

drop policy if exists members_update on public.trip_members;

create policy members_update on public.trip_members for update to authenticated

  using (user_id = auth.uid()) with check (user_id = auth.uid());


 

-- Budgets are personal: you set your own numbers, everyone can see the totals.

drop policy if exists tm_insert on public.budget_lines;

drop policy if exists budget_insert on public.budget_lines;

create policy budget_insert on public.budget_lines for insert to authenticated

  with check (user_id = auth.uid() and public.is_trip_member(trip_id));


 

drop policy if exists tm_update on public.budget_lines;

drop policy if exists budget_update on public.budget_lines;

create policy budget_update on public.budget_lines for update to authenticated

  using (user_id = auth.uid()) with check (user_id = auth.uid());


 

drop policy if exists tm_delete on public.budget_lines;

drop policy if exists budget_delete on public.budget_lines;

create policy budget_delete on public.budget_lines for delete to authenticated

  using (user_id = auth.uid());


 

-- An RSVP is yours alone: nobody answers for you, and clearing it is a delete.

drop policy if exists tm_insert on public.attendance;

drop policy if exists rsvp_insert on public.attendance;

create policy rsvp_insert on public.attendance for insert to authenticated

  with check (user_id = auth.uid() and public.is_trip_member(trip_id));


 

drop policy if exists tm_update on public.attendance;

drop policy if exists rsvp_update on public.attendance;

create policy rsvp_update on public.attendance for update to authenticated

  using (user_id = auth.uid()) with check (user_id = auth.uid());


 

drop policy if exists tm_delete on public.attendance;

drop policy if exists rsvp_delete on public.attendance;

create policy rsvp_delete on public.attendance for delete to authenticated

  using (user_id = auth.uid());


 

-- Same for a vote on a suggestion.

drop policy if exists tm_insert on public.suggestion_votes;

drop policy if exists sugvote_insert on public.suggestion_votes;

create policy sugvote_insert on public.suggestion_votes for insert to authenticated

  with check (user_id = auth.uid() and public.is_trip_member(trip_id));


 

drop policy if exists tm_update on public.suggestion_votes;

drop policy if exists sugvote_update on public.suggestion_votes;

create policy sugvote_update on public.suggestion_votes for update to authenticated

  using (user_id = auth.uid()) with check (user_id = auth.uid());


 

drop policy if exists tm_delete on public.suggestion_votes;

drop policy if exists sugvote_delete on public.suggestion_votes;

create policy sugvote_delete on public.suggestion_votes for delete to authenticated

  using (user_id = auth.uid());


 

-- A stop or a suggestion is edited and removed by whoever wrote it, or by an

-- organiser. Everyone can still add.

drop policy if exists tm_update on public.itinerary_items;

drop policy if exists stop_update on public.itinerary_items;

create policy stop_update on public.itinerary_items for update to authenticated

  using (created_by = auth.uid() or public.is_trip_admin(trip_id))

  with check (public.is_trip_member(trip_id));


 

drop policy if exists tm_delete on public.itinerary_items;

drop policy if exists stop_delete on public.itinerary_items;

create policy stop_delete on public.itinerary_items for delete to authenticated

  using (created_by = auth.uid() or public.is_trip_admin(trip_id));


 

drop policy if exists tm_update on public.suggestions;

drop policy if exists suggestion_update on public.suggestions;

create policy suggestion_update on public.suggestions for update to authenticated

  using (created_by = auth.uid() or public.is_trip_admin(trip_id))

  with check (public.is_trip_member(trip_id));


 

drop policy if exists tm_delete on public.suggestions;

drop policy if exists suggestion_delete on public.suggestions;

create policy suggestion_delete on public.suggestions for delete to authenticated

  using (

    created_by = auth.uid()

    or public.is_trip_admin(trip_id)

    or exists (                                    -- the stop's author may clear it

      select 1 from public.itinerary_items i

      where i.id = item_id and i.created_by = auth.uid()

    )

  );


 

-- A post is edited, pinned and removed by its author or an organiser.

-- Wrapping a question early is open to every member, so it goes through the

-- wrap_post RPC rather than a loose update policy.

drop policy if exists tm_update on public.posts;

drop policy if exists post_update on public.posts;

create policy post_update on public.posts for update to authenticated

  using (created_by = auth.uid() or public.is_trip_admin(trip_id))

  with check (public.is_trip_member(trip_id));


 

drop policy if exists tm_delete on public.posts;

drop policy if exists post_delete on public.posts;

create policy post_delete on public.posts for delete to authenticated

  using (created_by = auth.uid() or public.is_trip_admin(trip_id));


 

-- A reply belongs to whoever wrote it, and you never reply to your own

-- question: the round is asking the rest of the group.

drop policy if exists tm_insert on public.post_replies;

drop policy if exists reply_insert on public.post_replies;

create policy reply_insert on public.post_replies for insert to authenticated

  with check (

    user_id = auth.uid()

    and public.is_trip_member(trip_id)

    and not exists (

      select 1 from public.posts p

      where p.id = post_id and p.kind = 'question' and p.created_by = auth.uid()

    )

  );


 

drop policy if exists tm_update on public.post_replies;

drop policy if exists reply_update on public.post_replies;

create policy reply_update on public.post_replies for update to authenticated

  using (user_id = auth.uid()) with check (user_id = auth.uid());


 

drop policy if exists tm_delete on public.post_replies;

drop policy if exists reply_delete on public.post_replies;

create policy reply_delete on public.post_replies for delete to authenticated

  using (user_id = auth.uid() or public.is_trip_admin(trip_id));


 

-- A shared link is removed by whoever added it, or an organiser.

drop policy if exists tm_update on public.trip_links;

drop policy if exists link_update on public.trip_links;

create policy link_update on public.trip_links for update to authenticated

  using (created_by = auth.uid() or public.is_trip_admin(trip_id))

  with check (public.is_trip_member(trip_id));


 

drop policy if exists tm_delete on public.trip_links;

drop policy if exists link_delete on public.trip_links;

create policy link_delete on public.trip_links for delete to authenticated

  using (created_by = auth.uid() or public.is_trip_admin(trip_id));


 

-- A private checklist item is invisible to everyone but its author. This is

-- the policy that makes "just for me" real rather than a UI filter.

drop policy if exists tm_read on public.checklist_items;

drop policy if exists checklist_read on public.checklist_items;

create policy checklist_read on public.checklist_items for select to authenticated

  using (

    public.is_trip_member(trip_id)

    and (is_private = false or created_by = auth.uid())

  );


 

drop policy if exists tm_update on public.checklist_items;

drop policy if exists checklist_update on public.checklist_items;

create policy checklist_update on public.checklist_items for update to authenticated

  using (created_by = auth.uid() or (is_private = false and public.is_trip_member(trip_id)))

  with check (public.is_trip_member(trip_id));


 

drop policy if exists tm_delete on public.checklist_items;

drop policy if exists checklist_delete on public.checklist_items;

create policy checklist_delete on public.checklist_items for delete to authenticated

  using (created_by = auth.uid() or public.is_trip_admin(trip_id));


 

-- Ticking a checklist item is personal too: nobody can tick on your behalf.

drop policy if exists tm_insert on public.checklist_checks;

drop policy if exists check_insert on public.checklist_checks;

create policy check_insert on public.checklist_checks for insert to authenticated

  with check (user_id = auth.uid() and public.is_trip_member(trip_id));


 

drop policy if exists tm_update on public.checklist_checks;

drop policy if exists check_update on public.checklist_checks;

create policy check_update on public.checklist_checks for update to authenticated

  using (user_id = auth.uid()) with check (user_id = auth.uid());


 

drop policy if exists tm_delete on public.checklist_checks;

drop policy if exists check_delete on public.checklist_checks;

create policy check_delete on public.checklist_checks for delete to authenticated

  using (user_id = auth.uid());


 

-- ---------------------------------------------------------------------------

-- 5. Realtime

-- ---------------------------------------------------------------------------

do $$

declare tbl text;

begin

  foreach tbl in array array[

    'trips','trip_members','itinerary_items','suggestions','attendance','polls',

    'poll_votes','suggestion_votes','posts','post_replies','trip_links',

    'checklist_items','checklist_checks','emergency_contacts','budget_lines',

    'expenses','expense_shares','settlements','member_locations'

  ] loop

    begin

      execute format('alter publication supabase_realtime add table public.%I', tbl);

    exception when duplicate_object then null;

    end;

  end loop;

end $$;


 

-- ---------------------------------------------------------------------------

-- 6. Upgrading a project that already ran an earlier version of this file

--

-- The create-table statements above are skipped when a table already exists,

-- so these bring the older shape forward. All of it is safe to re-run.

-- ---------------------------------------------------------------------------


 

alter table public.trip_members    add column if not exists budget numeric(12,2) not null default 0;

alter table public.polls           add column if not exists show_voters boolean not null default true;
alter table public.polls           add column if not exists allow_multiple boolean not null default false;

alter table public.itinerary_items add column if not exists completed_at timestamptz;

alter table public.itinerary_items add column if not exists completed_by uuid references public.profiles(id) on delete set null;

alter table public.emergency_contacts add column if not exists for_user uuid references public.profiles(id) on delete cascade;

alter table public.checklist_items add column if not exists note text default '';

-- Poll votes used to have one row per user. Multiple-answer polls need one row
-- per selected option, so migrate the primary key to include option_index.
do $$
begin
  if exists (
    select 1 from pg_constraint
    where conrelid = 'public.poll_votes'::regclass
      and contype = 'p'
      and conname = 'poll_votes_pkey'
  ) then
    alter table public.poll_votes drop constraint poll_votes_pkey;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.poll_votes'::regclass
      and contype = 'p'
  ) then
    alter table public.poll_votes
      add constraint poll_votes_pkey_multi primary key (poll_id, user_id, option_index);
  end if;
end $$;

-- Database-level validation: closed polls and invalid option indexes are rejected
-- even if someone bypasses the TripSync interface.
create or replace function public.validate_poll_vote()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  p public.polls%rowtype;
begin
  select * into p from public.polls where id = new.poll_id;
  if not found then raise exception 'Poll not found'; end if;
  if p.closed then raise exception 'This poll is closed'; end if;
  if new.option_index < 0 or new.option_index >= jsonb_array_length(p.options) then
    raise exception 'Invalid poll option';
  end if;
  if not p.allow_multiple and exists (
    select 1 from public.poll_votes v
    where v.poll_id = new.poll_id
      and v.user_id = new.user_id
      and v.option_index <> new.option_index
  ) then
    raise exception 'This poll allows only one answer';
  end if;
  return new;
end $$;

drop trigger if exists validate_poll_vote on public.poll_votes;
create trigger validate_poll_vote
before insert or update on public.poll_votes
for each row execute function public.validate_poll_vote();


 

-- The checklist stopped being an assignment list and became a shared

-- reference list with personal ticks.

alter table public.checklist_items drop column if exists assigned_to;

alter table public.checklist_items drop column if exists is_done;


 

-- Budgets moved from one figure per trip to one per person.

alter table public.budget_lines add column if not exists user_id uuid references public.profiles(id) on delete cascade;

delete from public.budget_lines where user_id is null;   -- old trip-wide rows

do $$

begin

  alter table public.budget_lines alter column user_id set not null;

exception when others then null;

end $$;

alter table public.budget_lines drop constraint if exists budget_lines_trip_id_category_key;

do $$

begin

  alter table public.budget_lines add constraint budget_lines_trip_user_category_key

    unique (trip_id, user_id, category);

exception when duplicate_table then null;

     when duplicate_object then null;

end $$;


 

alter table public.trip_members add column if not exists seen_announcements_at timestamptz;

alter table public.suggestions  drop column if exists status;


 

-- Question rounds arrived after the first release; nothing to migrate beyond

-- the tables above, which the create-if-not-exists statements handle.


 

-- ---------------------------------------------------------------------------

-- 7. Board unification (revision c)

--

-- Announcements, question rounds and quick status became one feed. Existing

-- rows are copied across, keeping their ids and timestamps, and only then are

-- the old tables dropped. Guarded by to_regclass so a fresh install skips it.

-- ---------------------------------------------------------------------------


 

alter table public.trip_members add column if not exists seen jsonb not null default '{}'::jsonb;

alter table public.checklist_items add column if not exists is_private boolean not null default false;

alter table public.checklist_items drop column if exists note;


 

do $$

begin

  if to_regclass('public.announcements') is not null then

    insert into public.posts (id, trip_id, kind, title, body, pinned, created_by, created_at)

    select id, trip_id, 'notice', coalesce(title, ''), coalesce(nullif(body, ''), title),

           pinned, created_by, created_at

    from public.announcements

    on conflict (id) do nothing;

  end if;


 

  if to_regclass('public.questions') is not null then

    insert into public.posts (id, trip_id, kind, title, body, headcount,

                              closed_at, closed_by, created_by, created_at)

    select id, trip_id, 'question', '', body, greatest(1, headcount),

           closed_at, closed_by, asked_by, created_at

    from public.questions

    on conflict (id) do nothing;

  end if;


 

  if to_regclass('public.answers') is not null then

    insert into public.post_replies (id, trip_id, post_id, user_id, body, created_at)

    select a.id, a.trip_id, a.question_id, a.user_id, a.body, a.created_at

    from public.answers a

    where exists (select 1 from public.posts p where p.id = a.question_id)

    on conflict (id) do nothing;

  end if;


 

  if to_regclass('public.status_updates') is not null then

    insert into public.posts (id, trip_id, kind, title, body, state, created_by, created_at)

    select id, trip_id, 'notice', '', body, coalesce(state, 'ok'), user_id, created_at

    from public.status_updates

    on conflict (id) do nothing;

  end if;

end $$;


 

drop table if exists public.answers cascade;

drop table if exists public.questions cascade;

drop table if exists public.announcements cascade;

drop table if exists public.status_updates cascade;


 

alter table public.trip_members drop column if exists seen_announcements_at;


 

-- Loose ideas are gone: a suggestion now always belongs to a stop.

delete from public.suggestions where item_id is null;

do $$

begin

  alter table public.suggestions alter column item_id set not null;

exception when others then null;

end $$;


 

-- ---------------------------------------------------------------------------

-- 8. One admin role (revision d)

--

-- Owner and admin had identical rights, so the distinction was noise. Every

-- owner becomes an admin; trips.created_by still records who started the trip.

-- ---------------------------------------------------------------------------


 

update public.trip_members set role = 'admin' where role = 'owner';


 

do $$

begin

  if not exists (

    select 1 from pg_constraint where conname = 'trip_members_role_check'

  ) then

    alter table public.trip_members

      add constraint trip_members_role_check check (role in ('admin', 'member'));

  end if;

end $$;


 

-- ---------------------------------------------------------------------------

-- 9. One target for person columns (revision f)

--

-- Early tables pointed their person columns at auth.users, later ones at

-- public.profiles. Only a profiles reference can be embedded by PostgREST, so

-- a future query that wants to join a name through, say, itinerary_items

-- would fail for no visible reason. Every profile row already exists (the

-- signup trigger plus the backfill above), so repointing is safe.

-- ---------------------------------------------------------------------------


 

do $$

declare

  r record;

  fk text;

begin

  for r in

    select * from (values

      ('itinerary_items', 'created_by'), ('suggestions', 'created_by'),

      ('attendance', 'user_id'), ('polls', 'created_by'), ('poll_votes', 'user_id'),

      ('checklist_items', 'created_by'), ('emergency_contacts', 'created_by'),

      ('expenses', 'paid_by'), ('expenses', 'created_by'), ('expense_shares', 'user_id'),

      ('settlements', 'from_user'), ('settlements', 'to_user'), ('settlements', 'created_by'),

      ('member_locations', 'user_id'), ('trips', 'created_by')

    ) as t(tbl, col)

  loop

    -- only repoint rows that can be matched; a missing profile would fail the

    -- constraint, so make sure one exists first

    insert into public.profiles (id, full_name, phone)

    select u.id, coalesce(u.raw_user_meta_data->>'full_name', split_part(u.email, '@', 1)), ''

    from auth.users u

    on conflict (id) do nothing;


 

    select conname into fk

    from pg_constraint c

    join pg_class rel on rel.oid = c.conrelid

    where rel.relname = r.tbl and c.contype = 'f'

      and c.conkey = array[(

        select attnum from pg_attribute

        where attrelid = rel.oid and attname = r.col

      )::smallint]

    limit 1;


 

    if fk is not null then

      execute format('alter table public.%I drop constraint %I', r.tbl, fk);

    end if;


 

    begin

      execute format(

        'alter table public.%I add constraint %I foreign key (%I) references public.profiles(id) on delete cascade',

        r.tbl, r.tbl || '_' || r.col || '_profiles_fkey', r.col);

    exception when duplicate_object then null;

    end;

  end loop;

end $$;


 

-- ---------------------------------------------------------------------------

-- 10. Input constraints (revision g)

--

-- Found by adversarial testing: the schema accepted a javascript: URL as a

-- shared link (stored XSS), negative budgets, sub-paisa expenses, a poll whose

-- options were a bare string, whitespace-only titles, and 5,000-character

-- text. The interface guarded most of it; the database did not, and the

-- database is the only guard that holds when a request does not come from the

-- interface.

--

-- Each constraint is added defensively: if existing rows violate it, the add

-- is skipped with a notice rather than failing the whole script, so you can

-- clean up and re-run.

-- ---------------------------------------------------------------------------


 

do $$

declare

  r record;

begin

  for r in

    select * from (values

      -- a link must be a real web address, never a script or inline document

      ('trip_links', 'trip_links_url_web',

       $q$url ~* '^https?://[^\s]+$'$q$),

      ('trip_links', 'trip_links_title_len',

       $q$btrim(title) <> '' and length(title) <= 120$q$),


 

      -- money cannot be negative, and an expense must round to something

      ('trip_members', 'trip_members_budget_positive', $q$budget >= 0$q$),

      ('budget_lines', 'budget_lines_planned_positive', $q$planned >= 0$q$),

      ('trips', 'trips_budget_positive', $q$budget >= 0$q$),

      -- an upper bound is not a business rule, just a fat-finger catch: a

      -- settlement or expense with a few too many zeros should be rejected,

      -- not silently distort every balance on the trip

      ('expenses', 'expenses_amount_min', $q$amount >= 0.01$q$),

      ('expenses', 'expenses_amount_max', $q$amount <= 10000000$q$),

      ('settlements', 'settlements_amount_min', $q$amount >= 0.01$q$),

      ('settlements', 'settlements_amount_max', $q$amount <= 10000000$q$),

      ('budget_lines', 'budget_lines_planned_max', $q$planned <= 10000000$q$),

      ('trip_members', 'trip_members_budget_max', $q$budget <= 10000000$q$),

      ('trips', 'trips_budget_max', $q$budget <= 10000000$q$),


 

      -- a poll needs a real list of at least two things to choose between

      ('polls', 'polls_options_shape',

       $q$jsonb_typeof(options) = 'array'

          and jsonb_array_length(options) between 2 and 20$q$),

      ('polls', 'polls_question_len',

       $q$btrim(question) <> '' and length(question) <= 300$q$),


 

      -- text that is only whitespace renders as an empty row

      ('trips', 'trips_name_len', $q$btrim(name) <> '' and length(name) <= 120$q$),

      ('itinerary_items', 'itinerary_title_len',

       $q$btrim(title) <> '' and length(title) <= 200$q$),

      ('itinerary_items', 'itinerary_desc_len', $q$length(coalesce(description, '')) <= 2000$q$),

      ('posts', 'posts_body_len', $q$btrim(body) <> '' and length(body) <= 4000$q$),

      ('posts', 'posts_title_len', $q$length(coalesce(title, '')) <= 200$q$),

      ('post_replies', 'post_replies_body_len',

       $q$btrim(body) <> '' and length(body) <= 2000$q$),

      ('suggestions', 'suggestions_body_len',

       $q$btrim(body) <> '' and length(body) <= 2000$q$),

      ('checklist_items', 'checklist_title_len',

       $q$btrim(title) <> '' and length(title) <= 200$q$),

      ('emergency_contacts', 'contacts_name_len',

       $q$btrim(name) <> '' and length(name) <= 120$q$),

      ('emergency_contacts', 'contacts_phone_len',

       $q$btrim(phone) <> '' and length(phone) <= 40$q$),

      ('status_note', 'skip', $q$true$q$)

    ) as t(tbl, cname, expr)

  loop

    if to_regclass('public.' || r.tbl) is null then

      continue;

    end if;

    if exists (select 1 from pg_constraint where conname = r.cname) then

      continue;

    end if;

    begin

      execute format('alter table public.%I add constraint %I check (%s)',

                     r.tbl, r.cname, r.expr);

    exception

      when check_violation then

        raise notice 'skipped %: existing rows violate it, clean up and re-run', r.cname;

      when others then

        raise notice 'skipped %: %', r.cname, sqlerrm;

    end;

  end loop;

end $$;


 

-- ============================================================================
-- Web Push Notifications (added for TripSync)
-- ============================================================================

create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  endpoint text not null,
  p256dh text not null,
  auth text not null,
  user_agent text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint push_subscriptions_user_endpoint_unique unique (user_id, endpoint)
);

create index if not exists idx_push_subscriptions_user
  on public.push_subscriptions(user_id);

alter table public.push_subscriptions enable row level security;

drop policy if exists "Users can view own push subscriptions" on public.push_subscriptions;
create policy "Users can view own push subscriptions"
on public.push_subscriptions for select to authenticated
using (user_id = auth.uid());

drop policy if exists "Users can create own push subscriptions" on public.push_subscriptions;
create policy "Users can create own push subscriptions"
on public.push_subscriptions for insert to authenticated
with check (user_id = auth.uid());

drop policy if exists "Users can update own push subscriptions" on public.push_subscriptions;
create policy "Users can update own push subscriptions"
on public.push_subscriptions for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "Users can delete own push subscriptions" on public.push_subscriptions;
create policy "Users can delete own push subscriptions"
on public.push_subscriptions for delete to authenticated
using (user_id = auth.uid());

notify pgrst, 'reload schema';

-- ============================================================================
-- TripSync auth helper: prevent duplicate account creation from the UI
-- ============================================================================
-- This is used before signUp() so an existing email gets a clear message
-- instead of the generic Supabase confirmation response.
-- NOTE: this intentionally allows the public signup form to determine whether
-- an email is already registered. If you want email-enumeration protection,
-- remove this function/grants and rely on Supabase's generic auth response.

create or replace function public.email_exists(p_email text)
returns boolean
language sql
security definer
set search_path = public, auth
stable
as $$
  select exists (
    select 1
    from auth.users
    where lower(email) = lower(trim(p_email))
  );
$$;

revoke all on function public.email_exists(text) from public;
grant execute on function public.email_exists(text) to anon, authenticated;

notify pgrst, 'reload schema';

-- ============================================================================
-- TripSync hardening + notifications
-- Safe to re-run after the main schema above.
-- ============================================================================

-- Push subscriptions ---------------------------------------------------------
create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  endpoint text not null,
  p256dh text not null,
  auth text not null,
  user_agent text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint push_subscriptions_user_endpoint_unique unique (user_id, endpoint)
);

create index if not exists idx_push_subscriptions_user
  on public.push_subscriptions(user_id);

alter table public.push_subscriptions enable row level security;
drop policy if exists push_read on public.push_subscriptions;
drop policy if exists push_insert on public.push_subscriptions;
drop policy if exists push_update on public.push_subscriptions;
drop policy if exists push_delete on public.push_subscriptions;
create policy push_read on public.push_subscriptions for select to authenticated
  using (user_id = auth.uid());
create policy push_insert on public.push_subscriptions for insert to authenticated
  with check (user_id = auth.uid());
create policy push_update on public.push_subscriptions for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy push_delete on public.push_subscriptions for delete to authenticated
  using (user_id = auth.uid());

-- Personal per-trip alert switch. A missing row means alerts are enabled.
create table if not exists public.trip_alert_preferences (
  trip_id uuid not null references public.trips(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (trip_id, user_id)
);
alter table public.trip_alert_preferences enable row level security;
drop policy if exists alert_pref_read on public.trip_alert_preferences;
drop policy if exists alert_pref_insert on public.trip_alert_preferences;
drop policy if exists alert_pref_update on public.trip_alert_preferences;
drop policy if exists alert_pref_delete on public.trip_alert_preferences;
create policy alert_pref_read on public.trip_alert_preferences for select to authenticated
  using (user_id = auth.uid());
create policy alert_pref_insert on public.trip_alert_preferences for insert to authenticated
  with check (user_id = auth.uid() and public.is_trip_member(trip_id));
create policy alert_pref_update on public.trip_alert_preferences for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid() and public.is_trip_member(trip_id));
create policy alert_pref_delete on public.trip_alert_preferences for delete to authenticated
  using (user_id = auth.uid());

-- Do not let the broad trip-member policies override personal budget rules.
drop policy if exists tm_insert on public.budget_lines;
drop policy if exists tm_update on public.budget_lines;
drop policy if exists tm_delete on public.budget_lines;
drop policy if exists budget_insert on public.budget_lines;
drop policy if exists budget_update on public.budget_lines;
drop policy if exists budget_delete on public.budget_lines;
drop policy if exists budget_read on public.budget_lines;
create policy budget_read on public.budget_lines for select to authenticated
  using (public.is_trip_member(trip_id));
create policy budget_insert on public.budget_lines for insert to authenticated
  with check (user_id = auth.uid() and public.is_trip_member(trip_id));
create policy budget_update on public.budget_lines for update to authenticated
  using (user_id = auth.uid() and public.is_trip_member(trip_id))
  with check (user_id = auth.uid() and public.is_trip_member(trip_id));
create policy budget_delete on public.budget_lines for delete to authenticated
  using (user_id = auth.uid());

-- Recipient-only settlement confirmation. The person receiving the money
-- creates the settlement row; nobody else can manufacture a paid state.
drop policy if exists tm_insert on public.settlements;
drop policy if exists tm_update on public.settlements;
drop policy if exists tm_delete on public.settlements;
drop policy if exists settlement_read on public.settlements;
drop policy if exists settlement_insert on public.settlements;
drop policy if exists settlement_delete on public.settlements;
create policy settlement_read on public.settlements for select to authenticated
  using (public.is_trip_member(trip_id));
create policy settlement_insert on public.settlements for insert to authenticated
  with check (
    to_user = auth.uid()
    and created_by = auth.uid()
    and public.is_trip_member(trip_id)
    and exists (select 1 from public.trip_members m where m.trip_id = trip_id and m.user_id = from_user)
    and exists (select 1 from public.trip_members m where m.trip_id = trip_id and m.user_id = to_user)
  );
create policy settlement_delete on public.settlements for delete to authenticated
  using (to_user = auth.uid() or public.is_trip_admin(trip_id));

-- Prevent negative/over-budget personal allocations even if the UI is bypassed.
create or replace function public.enforce_budget_line_cap()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_budget numeric;
declare v_total numeric;
begin
  select budget into v_budget
  from public.trip_members
  where trip_id = new.trip_id and user_id = new.user_id
  for update;
  if v_budget is null then raise exception 'Trip member not found'; end if;
  select coalesce(sum(planned),0) into v_total
  from public.budget_lines
  where trip_id = new.trip_id and user_id = new.user_id;
  if v_total > v_budget then
    raise exception 'Category allocations cannot exceed the personal budget';
  end if;
  return new;
end $$;

drop trigger if exists budget_line_cap on public.budget_lines;
create trigger budget_line_cap
after insert or update on public.budget_lines
for each row execute function public.enforce_budget_line_cap();

create or replace function public.enforce_member_budget_cap()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_total numeric;
begin
  if new.budget < 0 then raise exception 'Budget cannot be negative'; end if;
  select coalesce(sum(planned),0) into v_total
  from public.budget_lines
  where trip_id = new.trip_id and user_id = new.user_id;
  if v_total > new.budget then
    raise exception 'Personal budget cannot be lower than category allocations';
  end if;
  return new;
end $$;

drop trigger if exists member_budget_cap on public.trip_members;
create trigger member_budget_cap
before update of budget on public.trip_members
for each row execute function public.enforce_member_budget_cap();

-- Trip date consistency at the database boundary.
create or replace function public.validate_trip_dates()
returns trigger language plpgsql as $$
begin
  if new.start_date is not null and new.end_date is not null and new.end_date < new.start_date then
    raise exception 'Trip end date cannot be before the start date';
  end if;
  return new;
end $$;
drop trigger if exists validate_trip_dates on public.trips;
create trigger validate_trip_dates
before insert or update of start_date, end_date on public.trips
for each row execute function public.validate_trip_dates();

create or replace function public.validate_itinerary_dates()
returns trigger language plpgsql security definer set search_path = public as $$
declare s date; e date;
begin
  select start_date, end_date into s, e from public.trips where id = new.trip_id;
  if s is not null and new.start_time::date < s then raise exception 'Stop is before the trip start date'; end if;
  if e is not null and new.start_time::date > e then raise exception 'Stop is after the trip end date'; end if;
  if new.end_time is not null and new.end_time < new.start_time then raise exception 'Stop end time cannot be before its start time'; end if;
  if e is not null and new.end_time is not null and new.end_time::date > e then raise exception 'Stop end date is outside the trip'; end if;
  return new;
end $$;
drop trigger if exists validate_itinerary_dates on public.itinerary_items;
create trigger validate_itinerary_dates
before insert or update of trip_id, start_time, end_time on public.itinerary_items
for each row execute function public.validate_itinerary_dates();

-- Poll invariants: trim, unique options, and at least two choices.
create or replace function public.validate_poll()
returns trigger language plpgsql security definer set search_path = public as $$
declare i integer; j integer; a text; b text;
begin
  if btrim(coalesce(new.question,'')) = '' then raise exception 'Poll question is required'; end if;
  if jsonb_typeof(new.options) <> 'array' or jsonb_array_length(new.options) < 2 or jsonb_array_length(new.options) > 20 then
    raise exception 'A poll needs between 2 and 20 options';
  end if;
  for i in 0..jsonb_array_length(new.options)-1 loop
    a := btrim(new.options->>i);
    if a = '' then raise exception 'Poll options cannot be empty'; end if;
    new.options := jsonb_set(new.options, array[i::text], to_jsonb(a), false);
    for j in i+1..jsonb_array_length(new.options)-1 loop
      b := btrim(new.options->>j);
      if lower(a) = lower(b) then raise exception 'Poll options must be different'; end if;
    end loop;
  end loop;
  return new;
end $$;
drop trigger if exists validate_poll on public.polls;
create trigger validate_poll
before insert or update of question, options on public.polls
for each row execute function public.validate_poll();

-- Poll vote RLS: the broad policy is retained for trip members but every vote
-- must belong to the signed-in voter.
drop policy if exists votes_write on public.poll_votes;
create policy votes_write on public.poll_votes for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and public.is_trip_member((select trip_id from public.polls p where p.id = poll_id)));

-- Helpful indexes for notifications and common lookups.
create index if not exists idx_trip_alert_preferences_trip_user
  on public.trip_alert_preferences(trip_id, user_id);

notify pgrst, 'reload schema';
