#!/usr/bin/env node

/**
 * Creates clearly labelled, non-loginable demo accounts and feed data for a
 * Norge360 development / staging project. It never updates or deletes data
 * outside the seed username suffix and invisible seed marker. Existing
 * active groups are used only as optional post context; this tool never
 * creates groups or changes group memberships.
 *
 * Required environment variables:
 *   SUPABASE_URL
 *   SUPABASE_SERVICE_ROLE_KEY
 *
 * Run a dry preview (default):
 *   node scripts/seed-community-demo.mjs
 *
 * Apply data:
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node scripts/seed-community-demo.mjs --apply
 */

import crypto from "node:crypto";

const shouldApply = process.argv.includes("--apply");
const supabaseURL = process.env.SUPABASE_URL?.replace(/\/$/, "");
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const profileCount = 100;
const postCount = 500;
// Keeps the data repeatable without showing a hashtag in the feed.
const marker = "\u2063norge360_seed_v1\u2063";

if (!supabaseURL || !serviceRoleKey) {
  console.error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY.");
  process.exit(1);
}

const firstNames = [
  "Ada", "Aisha", "Amira", "Anders", "Arda", "Aylin", "Berit", "Can", "Ceren", "David",
  "Derya", "Ece", "Eirik", "Elif", "Emre", "Erik", "Fatima", "Hanna", "Ida", "Ingrid",
  "Jonas", "Kari", "Leila", "Lina", "Maja", "Mehmet", "Mina", "Nadia", "Nora", "Ola",
  "Omar", "Pelin", "Rana", "Sara", "Sibel", "Sofia", "Tariq", "Tove", "Yasmin", "Yusuf"
];
const lastNames = [
  "Aasen", "Berg", "Dahl", "Demir", "Eide", "Foss", "Gundersen", "Hansen", "Iversen", "Jensen",
  "Kaya", "Larsen", "Madsen", "Nilsen", "Olsen", "Pettersen", "Rahman", "Solberg", "Yilmaz", "Østby"
];
const cities = ["Oslo", "Bergen", "Stavanger", "Trondheim", "Tromsø"];
const interests = ["newcomers", "families", "students", "work", "language_practice", "travel"];
function headers(extra = {}) {
  return {
    apikey: serviceRoleKey,
    Authorization: `Bearer ${serviceRoleKey}`,
    "Content-Type": "application/json",
    ...extra
  };
}

async function request(path, options = {}) {
  const response = await fetch(`${supabaseURL}${path}`, {
    ...options,
    headers: headers(options.headers)
  });
  const text = await response.text();
  let body;
  try { body = text ? JSON.parse(text) : null; } catch { body = text; }
  if (!response.ok) {
    throw new Error(`${options.method ?? "GET"} ${path} failed (${response.status}): ${typeof body === "string" ? body : JSON.stringify(body)}`);
  }
  return body;
}

async function rest(path, options = {}) {
  return request(`/rest/v1/${path}`, options);
}

function chunk(items, size) {
  return Array.from({ length: Math.ceil(items.length / size) }, (_, index) => items.slice(index * size, (index + 1) * size));
}

function demoProfile(index) {
  const firstName = firstNames[index % firstNames.length];
  const lastName = lastNames[Math.floor(index / firstNames.length) % lastNames.length];
  const city = cities[index % cities.length];
  const status = ["planning_move", "new_to_norway", "resident", "visitor"][index % 4];
  const username = `${firstName}_${lastName}`.toLowerCase().replace("ø", "o") + `_${String(index + 1).padStart(2, "0")}_n360`;
  return {
    username,
    legacyUsername: `demo_seed_${String(index + 1).padStart(3, "0")}`,
    email: `seed-${String(index + 1).padStart(3, "0")}@example.invalid`,
    display_name: `${firstName} ${lastName}`,
    preferred_locale: index % 5 === 0 ? "tr" : index % 7 === 0 ? "nb" : "en",
    norway_status: status,
    city_or_region: city,
    public_languages: index % 3 === 0 ? ["en", "tr"] : ["en", "nb"],
    interests: [interests[index % interests.length], interests[(index + 2) % interests.length]],
    is_public: true,
    moderation_state: "active"
  };
}

function seededBody(index, city) {
  const openings = [
    "Has anyone found a calm place to work for a few hours?", "Small win today: I completed another moving task.",
    "I am comparing neighbourhoods for everyday life.", "For language practice, I am trying to build a steady routine.",
    "A gentle reminder for newcomers: official requirements can change.", "One everyday habit made my first weeks much easier.",
    "I am planning a low-key weekend walk.", "Question for students: finding social activities takes time.",
    "I am balancing a new job, Norwegian practice and exploring the city.", "I found a food shop that made weekday cooking easier.",
    "For families, the first weeks in a new area can be a lot.", "I am making a practical arrival checklist.",
    "I am looking for an indoor activity for a rainy afternoon.", "A move can feel overwhelming, even when it is exciting.",
    "I would love to see more relaxed community activities.", "I am interested in a short language exchange.",
    "I am trying to keep track of transport and everyday appointments.", "I will be visiting soon and want low-cost local ideas.",
    "I have been thinking about why people choose their city.", "Today I learned a useful Norwegian phrase."
  ];
  const details = [
    `I am based around ${city} at the moment.`, "I am still learning what is practical day to day.",
    "I would rather start with something simple than over-plan.", "It would be great to hear different experiences.",
    "I am especially interested in options reachable by public transport.", "A welcoming atmosphere matters more than anything fancy.",
    "I am keeping notes so I can pass useful ideas on to the next newcomer."
  ];
  const questions = [
    "What worked well for you?", "Any tips or places you would recommend?", "How did you approach this?",
    "What would you do differently next time?", "I would appreciate a few practical ideas.",
    "Does anyone have a small suggestion to share?", "What made the biggest difference for you?",
    "I am curious how others handle this.", "Would love to hear your perspective.", "Thanks in advance for any advice."
  ];
  const angles = [
    "I am thinking about weekday routines.", "I am keeping the budget modest.", "I am new to the area.",
    "I am travelling without a car.", "I am hoping to meet people gradually.", "I prefer a quiet setting.",
    "I am planning around a family schedule.", "I am fitting this around work.", "I am learning one step at a time.",
    "I am interested in practical local knowledge.", "I am collecting ideas for the coming month."
  ];
  return `${openings[index % openings.length]} ${details[index % details.length]} ${angles[index % angles.length]} ${questions[index % questions.length]}${marker}`;
}

async function createAuthUser(profile) {
  const password = `${crypto.randomBytes(18).toString("base64url")}Aa1!`;
  const response = await request("/auth/v1/admin/users", {
    method: "POST",
    body: JSON.stringify({
      email: profile.email,
      password,
      email_confirm: true,
      user_metadata: { demo_seed: true, username: profile.username }
    })
  });
  const id = response?.id ?? response?.user?.id;
  if (!id) throw new Error(`No user id returned for ${profile.username}.`);
  return id;
}

async function main() {
  const profiles = Array.from({ length: profileCount }, (_, index) => demoProfile(index));
  if (!shouldApply) {
    console.log(`${profiles.length} demo profile target; ${postCount} demo posts.`);
    console.log("Posts use existing active groups when available; no groups or memberships are created.");
    console.log("Dry run only. Add --apply to create data.");
    return;
  }

  const [legacyProfiles, naturalProfiles] = await Promise.all([
    rest("community_profiles?select=user_id,username&username=like.demo_seed_*", { headers: { Accept: "application/json" } }),
    rest("community_profiles?select=user_id,username&username=like.*_n360", { headers: { Accept: "application/json" } })
  ]);
  const existingProfiles = [...legacyProfiles, ...naturalProfiles];
  const idsByUsername = new Map(existingProfiles.map((row) => [row.username, row.user_id]));
  const missingProfiles = profiles.filter((profile) => !idsByUsername.has(profile.username) && !idsByUsername.has(profile.legacyUsername));

  console.log(`${profiles.length} demo profile target; ${missingProfiles.length} auth users need creating.`);
  console.log(`${postCount} demo posts will be ensured. Existing active groups may be used as post context.`);

  for (const profile of missingProfiles) {
    const id = await createAuthUser(profile);
    idsByUsername.set(profile.username, id);
  }

  const profileRows = profiles.map(({ email, legacyUsername, ...profile }) => ({
    ...profile,
    user_id: idsByUsername.get(profile.username) ?? idsByUsername.get(legacyUsername)
  }));
  for (const profile of profileRows) {
    // The first run may have created this account under the legacy seed
    // username. Keep the generated posts bound to the same auth user after
    // moving that profile to its natural-looking username.
    idsByUsername.set(profile.username, profile.user_id);
  }
  if (profileRows.some((profile) => !profile.user_id)) {
    throw new Error("A demo profile could not be matched to its auth user; no posts were created.");
  }
  for (const batch of chunk(profileRows, 100)) {
    await rest("community_profiles?on_conflict=user_id", {
      method: "POST",
      headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
      body: JSON.stringify(batch)
    });
  }

  const availableGroups = await rest("community_groups?select=id,slug&order=created_at.asc&limit=12", {
    headers: { Accept: "application/json" }
  });

  const existingPosts = await rest(`community_posts?select=id&body=ilike.*${encodeURIComponent(marker)}*`, {
    headers: { Accept: "application/json", Range: "0-999" }
  });
  const postsToCreate = Math.max(0, postCount - existingPosts.length);
  if (postsToCreate > 0) {
    const now = Date.now();
    const posts = Array.from({ length: postsToCreate }, (_, index) => {
      const profile = profiles[(existingPosts.length + index) % profiles.length];
      const group = availableGroups.length > 0 && (existingPosts.length + index) % 3 !== 0
        ? availableGroups[(existingPosts.length + index) % availableGroups.length]
        : null;
      return {
        author_id: idsByUsername.get(profile.username),
        group_id: group?.id ?? null,
        body: seededBody(existingPosts.length + index, profile.city_or_region),
        kind: ["question", "update", "recommendation"][(existingPosts.length + index) % 3],
        moderation_state: "active",
        created_at: new Date(now - (existingPosts.length + index) * 67 * 60 * 1000).toISOString()
      };
    });
    for (const batch of chunk(posts, 100)) {
      await rest("community_posts", {
        method: "POST",
        headers: { Prefer: "return=minimal" },
        body: JSON.stringify(batch)
      });
    }
  }

  console.log(`Done. ${profiles.length} demo profiles and ${postCount} marked demo posts are available.`);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
