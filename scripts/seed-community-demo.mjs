#!/usr/bin/env node

/**
 * Creates clearly labelled, non-loginable demo accounts and community data for
 * a Norge360 development / staging project.
 *
 * The seed is intentionally self-contained and repeatable:
 * - it only creates or updates records with the n360 demo username/marker;
 * - it never deletes data;
 * - it uses the service role only from this local script;
 * - group/event creation uses a short-lived authenticated seed-owner session so
 *   the production security-definer boundaries are exercised;
 * - all media is synthetic and uploaded to Supabase Storage.
 *
 * Required only for --apply:
 *   SUPABASE_URL
 *   SUPABASE_SERVICE_ROLE_KEY
 *
 * Preview the default load:
 *   node scripts/seed-community-demo.mjs
 *
 * Apply the default load (1,000 users, 1,000 posts, 24 groups,
 * 180 events and 5,000 comments):
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
 *     node scripts/seed-community-demo.mjs --apply
 *
 * Counts can be overridden for a smaller local smoke test:
 *   node scripts/seed-community-demo.mjs --apply --users=20 --posts=30 \
 *     --groups=4 --events=8 --comments=60
 */

import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const shouldApply = process.argv.includes("--apply");
const supabaseURL = process.env.SUPABASE_URL?.replace(/\/$/, "");
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const assetDirectory = path.join(scriptDirectory, "seed-assets");

const counts = {
  profiles: numericOption("users", process.env.N360_SEED_USERS, 1_000),
  posts: numericOption("posts", process.env.N360_SEED_POSTS, 1_000),
  groups: numericOption("groups", process.env.N360_SEED_GROUPS, 24),
  events: numericOption("events", process.env.N360_SEED_EVENTS, 180),
  comments: numericOption("comments", process.env.N360_SEED_COMMENTS, 5_000)
};

const seedVersion = "v2";
const seedUsernamePrefix = "n360_";
const postMarker = `\u2063norge360_seed_${seedVersion}\u2063`;
const eventMarker = `\u2063norge360_event_${seedVersion}\u2063`;
const commentMarker = `\u2063norge360_comment_${seedVersion}\u2063`;
const ownerPassword = process.env.N360_SEED_OWNER_PASSWORD ?? "Norge360Seed!2026";
const pageSize = 1_000;

const firstNames = [
  "Ada", "Aisha", "Amira", "Anders", "Arda", "Aylin", "Berit", "Can", "Ceren", "David",
  "Derya", "Ece", "Eirik", "Elif", "Emre", "Erik", "Fatima", "Hanna", "Ida", "Ingrid",
  "Jonas", "Kari", "Leila", "Lina", "Maja", "Mehmet", "Mina", "Nadia", "Nora", "Ola",
  "Omar", "Pelin", "Rana", "Sara", "Sibel", "Sofia", "Tariq", "Tove", "Yasmin", "Yusuf"
];
const lastNames = [
  "Aasen", "Berg", "Dahl", "Demir", "Eide", "Foss", "Gundersen", "Hansen", "Iversen", "Jensen",
  "Kaya", "Larsen", "Madsen", "Nilsen", "Olsen", "Pettersen", "Rahman", "Solberg", "Yilmaz", "Ostby"
];
const cities = ["Oslo", "Bergen", "Stavanger", "Trondheim", "Tromso"];
const locales = ["en", "nb", "tr", "ar", "fa", "fr", "es", "de", "uk", "ru", "pl", "so", "ti", "am", "ur", "fa-AF"];
const interests = ["newcomers", "families", "students", "work", "language_practice", "travel"];
const postKinds = ["question", "update", "recommendation"];

const assetSpecs = {
  avatars: [
    { file: "avatar-1.jpg", path: `seed-${seedVersion}/avatar-1.jpg`, width: 256, height: 256 },
    { file: "avatar-2.jpg", path: `seed-${seedVersion}/avatar-2.jpg`, width: 256, height: 256 },
    { file: "avatar-3.jpg", path: `seed-${seedVersion}/avatar-3.jpg`, width: 256, height: 256 },
    { file: "avatar-4.jpg", path: `seed-${seedVersion}/avatar-4.jpg`, width: 256, height: 256 }
  ],
  covers: [
    { file: "cover-meetup.jpg", path: `seed-${seedVersion}/cover-meetup.jpg`, width: 1080, height: 720 },
    { file: "cover-waterfront.jpg", path: `seed-${seedVersion}/cover-waterfront.jpg`, width: 1080, height: 720 },
    { file: "cover-cafe.jpg", path: `seed-${seedVersion}/cover-cafe.jpg`, width: 720, height: 720 }
  ],
  posts: [
    { file: "post-meetup.jpg", width: 960, height: 640 },
    { file: "post-waterfront.jpg", width: 960, height: 640 },
    { file: "post-cafe.jpg", width: 640, height: 640 }
  ]
};

function numericOption(name, environmentValue, fallback) {
  const argument = process.argv.find((value) => value.startsWith(`--${name}=`));
  const raw = argument ? argument.slice(name.length + 3) : environmentValue;
  const parsed = Number.parseInt(raw ?? String(fallback), 10);
  if (!Number.isInteger(parsed) || parsed < 0) {
    throw new Error(`Invalid --${name} value: ${raw}`);
  }
  return parsed;
}

function headers(extra = {}, accessToken = serviceRoleKey) {
  return {
    apikey: serviceRoleKey,
    Authorization: `Bearer ${accessToken}`,
    "Content-Type": "application/json",
    ...extra
  };
}

async function request(pathname, options = {}) {
  const {
    accessToken = serviceRoleKey,
    headers: extraHeaders,
    retry = 2,
    ...fetchOptions
  } = options;
  let attempt = 0;
  while (true) {
    const response = await fetch(`${supabaseURL}${pathname}`, {
      ...fetchOptions,
      headers: headers(extraHeaders, accessToken)
    });
    const text = await response.text();
    let body;
    try { body = text ? JSON.parse(text) : null; } catch { body = text; }
    if (response.ok) return body;

    const error = new Error(
      `${fetchOptions.method ?? "GET"} ${pathname} failed (${response.status}): ${
        typeof body === "string" ? body : JSON.stringify(body)
      }`
    );
    error.status = response.status;
    if (attempt >= retry || (response.status < 500 && response.status !== 429)) throw error;
    await new Promise((resolve) => setTimeout(resolve, 250 * (attempt + 1)));
    attempt += 1;
  }
}

async function rest(pathname, options = {}) {
  return request(`/rest/v1/${pathname}`, options);
}

async function rpc(functionName, payload, accessToken) {
  return request(`/rest/v1/rpc/${functionName}`, {
    method: "POST",
    accessToken,
    body: JSON.stringify(payload)
  });
}

function chunk(items, size) {
  return Array.from({ length: Math.ceil(items.length / size) }, (_, index) =>
    items.slice(index * size, (index + 1) * size)
  );
}

async function concurrent(items, limit, worker) {
  const results = new Array(items.length);
  let nextIndex = 0;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (true) {
      const index = nextIndex++;
      if (index >= items.length) return;
      results[index] = await worker(items[index], index);
    }
  });
  await Promise.all(workers);
  return results;
}

async function getRows(resource, query, options = {}) {
  const rows = [];
  const size = options.pageSize ?? pageSize;
  for (let offset = 0; ; offset += size) {
    const page = await rest(`${resource}?${query}&limit=${size}&offset=${offset}`, {
      headers: { Accept: "application/json", Range: `${offset}-${offset + size - 1}` }
    });
    rows.push(...(Array.isArray(page) ? page : []));
    if (!Array.isArray(page) || page.length < size) return rows;
  }
}

function slugPart(value) {
  return value
    .toLowerCase()
    .replaceAll("ø", "o")
    .replaceAll(/[^a-z0-9]+/g, "-")
    .replaceAll(/^-|-$/g, "");
}

function demoProfile(index) {
  const firstName = firstNames[index % firstNames.length];
  const lastName = lastNames[Math.floor(index / firstNames.length) % lastNames.length];
  const city = cities[index % cities.length];
  const locale = locales[index % locales.length];
  const status = ["planning_move", "new_to_norway", "resident", "visitor"][index % 4];
  const username = `${seedUsernamePrefix}${slugPart(city).slice(0, 3)}_${firstName.slice(0, 3).toLowerCase()}_${String(index + 1).padStart(4, "0")}`;
  const languages = Array.from(new Set([locale, "en"]));
  return {
    username,
    email: `norge360-seed-${String(index + 1).padStart(4, "0")}@example.invalid`,
    display_name: `${firstName} ${lastName}`,
    preferred_locale: locale,
    norway_status: status,
    city_or_region: city,
    public_languages: languages,
    interests: [interests[index % interests.length], interests[(index + 2) % interests.length]],
    is_public: true,
    show_norway_status: true,
    show_location: true,
    biography: [
      `Exploring everyday life in ${city}.`,
      `New to ${city}; collecting practical local tips.`,
      "Interested in language practice and friendly meetups.",
      "Finding a steady rhythm between work and Norway."
    ][index % 4],
    avatar_path: assetSpecs.avatars[index % assetSpecs.avatars.length].path,
    cover_path: assetSpecs.covers[index % assetSpecs.covers.length].path
  };
}

function seededPost(index, profile, groupID) {
  const openings = [
    "What helped you feel at home here?",
    "Small win today: another moving task is done.",
    "I am comparing neighbourhoods for everyday life.",
    "I am trying to build a steady Norwegian practice routine.",
    "A practical reminder for newcomers: official requirements can change.",
    "One everyday habit made my first weeks much easier.",
    "I am planning a low-key weekend walk.",
    "Question for students: how did you find social activities?",
    "I am balancing a new job, Norwegian practice and exploring the city.",
    "I found a food shop that made weekday cooking easier.",
    "For families, the first weeks in a new area can be a lot.",
    "I am making a practical arrival checklist.",
    "I am looking for an indoor activity for a rainy afternoon.",
    "A move can feel overwhelming, even when it is exciting.",
    "I would love to see more relaxed community activities.",
    "I am interested in a short language exchange."
  ];
  const details = [
    `I am based around ${profile.city_or_region} at the moment.`,
    "I am still learning what is practical day to day.",
    "I would rather start with something simple than over-plan.",
    "A welcoming atmosphere matters more than anything fancy.",
    "I am keeping notes so I can pass useful ideas on to the next newcomer."
  ];
  const questions = [
    "What worked well for you?",
    "Any tips or places you would recommend?",
    "How did you approach this?",
    "What would you do differently next time?",
    "Would love to hear your perspective."
  ];
  return {
    id: crypto.randomUUID(),
    author_id: profile.user_id,
    group_id: groupID,
    title: [
      `Everyday Norway: ${profile.city_or_region}`,
      "A practical newcomer question",
      "A small local discovery",
      "Community tip for this week"
    ][index % 4],
    body: `${openings[index % openings.length]} ${details[index % details.length]} ${questions[index % questions.length]} ${postMarker}`,
    kind: postKinds[index % postKinds.length],
    moderation_state: "active",
    created_at: new Date(Date.now() - index * 45 * 60 * 1000).toISOString()
  };
}

function seededGroup(index) {
  const city = cities[index % cities.length];
  const cityGroup = index % 2 === 0;
  const topics = cityGroup
    ? ["Weekend Walks", "Everyday Questions", "Newcomer Coffee", "Family Routines", "Local Transport"]
    : ["Language Practice", "Students in Norway", "International Cooking", "Outdoor Beginners", "Creative Meetups"];
  const topic = topics[Math.floor(index / 2) % topics.length];
  const name = cityGroup ? `${city} ${topic}` : topic;
  return {
    name: `${name} ${String(index + 1).padStart(2, "0")}`,
    slug: `n360-demo-${slugPart(name)}-${String(index + 1).padStart(2, "0")}`,
    description: cityGroup
      ? `A synthetic Norge360 demo group for practical ${topic.toLowerCase()} conversations in ${city}.`
      : `A synthetic Norge360 demo group for respectful ${topic.toLowerCase()} across Norway.`,
    scope: cityGroup ? "city" : "interest",
    city_or_region: cityGroup ? city : null,
    visibility: "public"
  };
}

function eventDescription(index, city) {
  return `A synthetic Norge360 demo event for meeting people and sharing practical local ideas in ${city}. Community experience only; check official sources for procedural guidance. ${eventMarker}`;
}

function seededComment(index, profile) {
  const replies = [
    "That sounds useful, thanks for sharing.",
    "I had a similar experience when I arrived.",
    "This is a helpful idea for a calm first step.",
    "I will keep this in mind for next week.",
    "A few practical suggestions can make a big difference.",
    "Hope the next part of your move goes smoothly."
  ];
  return `${replies[index % replies.length]} I am also learning my way around ${profile.city_or_region}. ${commentMarker}`;
}

function storageObjectPath(bucket, storagePath) {
  const encoded = storagePath.split("/").map(encodeURIComponent).join("/");
  return `/storage/v1/object/${encodeURIComponent(bucket)}/${encoded}`;
}

async function uploadStorage(bucket, storagePath, data, contentType = "image/jpeg") {
  await request(storageObjectPath(bucket, storagePath), {
    method: "POST",
    headers: {
      "Content-Type": contentType,
      "x-upsert": "true",
      "cache-control": "3600"
    },
    body: data
  });
}

async function loadAssets() {
  const assets = new Map();
  const specs = [
    ...assetSpecs.avatars.map((spec) => ({ ...spec, bucket: "avatars" })),
    ...assetSpecs.covers.map((spec) => ({ ...spec, bucket: "profile-media" })),
    ...assetSpecs.posts.map((spec) => ({ ...spec, bucket: "post-media", path: null }))
  ];
  for (const spec of specs) {
    const filePath = path.join(assetDirectory, spec.file);
    assets.set(spec.file, { ...spec, data: await fs.readFile(filePath) });
  }
  return assets;
}

async function uploadBaseAssets(assets) {
  const baseAssets = [
    ...assetSpecs.avatars.map((spec) => ({ ...spec, bucket: "avatars" })),
    ...assetSpecs.covers.map((spec) => ({ ...spec, bucket: "profile-media" }))
  ];
  await concurrent(baseAssets, 4, async (spec) => {
    await uploadStorage(spec.bucket, spec.path, assets.get(spec.file).data);
  });
}

async function listAuthUsers() {
  const users = [];
  for (let page = 1; ; page += 1) {
    const response = await request(`/auth/v1/admin/users?page=${page}&per_page=${pageSize}`);
    const pageUsers = response?.users ?? [];
    users.push(...pageUsers);
    if (pageUsers.length < pageSize) return users;
  }
}

async function createAuthUser(profile) {
  const password = `${crypto.randomBytes(18).toString("base64url")}Aa1!`;
  const response = await request("/auth/v1/admin/users", {
    method: "POST",
    body: JSON.stringify({
      email: profile.email,
      password,
      email_confirm: true,
      user_metadata: { demo_seed: true, seed_version: seedVersion, username: profile.username }
    })
  });
  const id = response?.id ?? response?.user?.id;
  if (!id) throw new Error(`No user id returned for ${profile.username}.`);
  return id;
}

async function prepareProfiles() {
  const profiles = Array.from({ length: counts.profiles }, (_, index) => demoProfile(index));
  const [existingProfiles, existingAuthUsers] = await Promise.all([
    getRows("community_profiles", "select=user_id,username&username=like.n360_*&order=username.asc"),
    listAuthUsers()
  ]);
  const idsByUsername = new Map(existingProfiles.map((row) => [row.username, row.user_id]));
  const authByEmail = new Map(existingAuthUsers.filter((user) => user.email).map((user) => [user.email, user]));
  const missingProfiles = profiles.filter((profile) => !idsByUsername.has(profile.username));
  console.log(`${profiles.length} profile target; ${missingProfiles.length} new auth users needed.`);

  await concurrent(missingProfiles, 10, async (profile) => {
    const existingAuthUser = authByEmail.get(profile.email);
    const userID = existingAuthUser?.id ?? await createAuthUser(profile);
    idsByUsername.set(profile.username, userID);
    if (!existingAuthUser) authByEmail.set(profile.email, { id: userID, email: profile.email });
  });

  const profileRows = profiles.map(({ email, ...profile }) => ({
    ...profile,
    user_id: idsByUsername.get(profile.username)
  }));
  if (profileRows.some((profile) => !profile.user_id)) {
    throw new Error("A demo profile could not be matched to its auth user.");
  }
  for (const batch of chunk(profileRows, 100)) {
    await rest("community_profiles?on_conflict=user_id", {
      method: "POST",
      headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
      body: JSON.stringify(batch)
    });
  }
  const accountProfileRows = profileRows.map((profile) => ({
    user_id: profile.user_id,
    preferred_locale: profile.preferred_locale
  }));
  for (const batch of chunk(accountProfileRows, 100)) {
    await rest("user_account_profiles?on_conflict=user_id", {
      method: "POST",
      headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
      body: JSON.stringify(batch)
    });
  }
  return { profiles: profileRows, authUsers: Array.from(authByEmail.values()) };
}

async function ownerSession(ownerProfile, existingAuthUsers) {
  const existing = existingAuthUsers.find((user) => user.id === ownerProfile.user_id);
  if (!existing) {
    throw new Error("Seed owner auth user was not found.");
  }
  await request(`/auth/v1/admin/users/${encodeURIComponent(ownerProfile.user_id)}`, {
    method: "PUT",
    body: JSON.stringify({ password: ownerPassword })
  });
  const response = await request("/auth/v1/token?grant_type=password", {
    method: "POST",
    headers: { apikey: serviceRoleKey },
    body: JSON.stringify({ email: existing.email, password: ownerPassword })
  });
  if (!response?.access_token) throw new Error("Could not create the seed owner session.");
  return response.access_token;
}

async function ensureGroups(ownerToken, existingGroups, ownerID, assets) {
  const existingBySlug = new Map(existingGroups.map((group) => [group.slug, group]));
  const groupDefinitions = Array.from({ length: counts.groups }, (_, index) => seededGroup(index));
  const missing = groupDefinitions.filter((group) => !existingBySlug.has(group.slug));
  console.log(`${groupDefinitions.length} demo group target; ${missing.length} new groups needed.`);
  const created = await concurrent(missing, 3, async (group) => {
    const createdGroup = await rpc("create_community_group", {
      group_name: group.name,
      group_slug: group.slug,
      group_description: group.description,
      group_scope: group.scope,
      group_city_or_region: group.city_or_region,
      group_visibility: group.visibility
    }, ownerToken);
    return createdGroup;
  });
  for (const group of created) existingBySlug.set(group.slug, group);
  const groups = groupDefinitions.map((definition) => existingBySlug.get(definition.slug)).filter(Boolean);

  const groupPhotoSpecs = assetSpecs.covers;
  await concurrent(groups, 3, async (group, index) => {
    const photoPath = `${group.id}/group.jpg`;
    const photo = assets.get(groupPhotoSpecs[index % groupPhotoSpecs.length].file);
    await uploadStorage("group-media", photoPath, photo.data);
    await rest(`community_groups?id=eq.${encodeURIComponent(group.id)}`, {
      method: "PATCH",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({ photo_path: photoPath })
    });
  });
  return groups.map((group) => ({ ...group, created_by: group.created_by ?? ownerID }));
}

async function ensureMemberships(groups, profiles) {
  if (groups.length === 0 || profiles.length === 0) return;
  const ownerByGroup = new Map(groups.map((group) => [group.id, group.created_by]));
  const rows = [];
  for (let index = 0; index < profiles.length; index += 1) {
    const groupIndexes = Array.from(new Set([
      index % groups.length,
      (index * 7 + 3) % groups.length,
      (index * 13 + 5) % groups.length
    ]));
    for (const groupIndex of groupIndexes) {
      const groupID = groups[groupIndex].id;
      if (profiles[index].user_id === ownerByGroup.get(groupID)) continue;
      rows.push({ group_id: groupID, user_id: profiles[index].user_id, role: "member" });
    }
  }
  for (const batch of chunk(rows, 200)) {
    await rest("community_group_memberships?on_conflict=group_id,user_id", {
      method: "POST",
      headers: { Prefer: "resolution=ignore-duplicates,return=minimal" },
      body: JSON.stringify(batch)
    });
  }
  console.log(`${rows.length} demo group memberships ensured.`);
}

async function ensurePosts(profiles, groups) {
  const existingPosts = await getRows(
    "community_posts",
    `select=id,author_id,group_id,title,body,kind,created_at&body=ilike.*norge360_seed*&order=created_at.asc`
  );
  const postsToCreate = Math.max(0, counts.posts - existingPosts.length);
  console.log(`${counts.posts} post target; ${postsToCreate} new posts needed.`);
  const groupIDs = groups.map((group) => group.id);
  const posts = Array.from({ length: postsToCreate }, (_, offset) => {
    const index = existingPosts.length + offset;
    const profile = profiles[index % profiles.length];
    const groupID = groupIDs.length > 0 && index % 5 !== 0 ? groupIDs[index % groupIDs.length] : null;
    return seededPost(index, profile, groupID);
  });
  for (const batch of chunk(posts, 100)) {
    await rest("community_posts", {
      method: "POST",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify(batch)
    });
  }
  return [...existingPosts, ...posts];
}

async function ensurePostMedia(posts, assets) {
  if (posts.length === 0) return 0;
  const existingMedia = await getRows("community_post_media", "select=post_id,storage_path&order=created_at.asc");
  const mediaByPost = new Map(existingMedia.map((media) => [media.post_id, media]));
  const visualTarget = Math.ceil(Math.min(counts.posts, posts.length) * 0.86);
  const existingVisualCount = posts.slice(0, counts.posts).filter((post) => mediaByPost.has(post.id)).length;
  const missingVisualCount = Math.max(0, visualTarget - existingVisualCount);
  const mediaTargets = posts
    .slice(0, counts.posts)
    .filter((post) => !mediaByPost.has(post.id))
    .slice(0, missingVisualCount);
  console.log(`${visualTarget} visual post target; ${mediaTargets.length} new post images needed.`);

  const mediaRows = await concurrent(mediaTargets, 8, async (post, index) => {
    const spec = assetSpecs.posts[index % assetSpecs.posts.length];
    const asset = assets.get(spec.file);
    const storagePath = `seed-${seedVersion}/posts/${post.id}.jpg`;
    await uploadStorage("post-media", storagePath, asset.data);
    return {
      post_id: post.id,
      storage_path: storagePath,
      sort_order: 0,
      width: spec.width,
      height: spec.height
    };
  });
  for (const batch of chunk(mediaRows, 100)) {
    await rest("community_post_media?on_conflict=post_id,sort_order", {
      method: "POST",
      headers: { Prefer: "resolution=ignore-duplicates,return=minimal" },
      body: JSON.stringify(batch)
    });
  }
  return mediaRows.length;
}

async function ensureEvents(ownerToken, groups) {
  const existingEvents = await getRows(
    "community_events",
    `select=id,title,description,group_id,host_id,starts_at&description=ilike.*norge360_event_${seedVersion}*&order=starts_at.asc`
  );
  const eventsToCreate = Math.max(0, counts.events - existingEvents.length);
  console.log(`${counts.events} event target; ${eventsToCreate} new events needed.`);
  if (eventsToCreate === 0) return existingEvents;
  const groupIDs = groups.map((group) => group.id);
  const eventIndexes = Array.from({ length: eventsToCreate }, (_, offset) => existingEvents.length + offset);
  const created = await concurrent(eventIndexes, 4, async (index) => {
    const groupID = groupIDs.length > 0 && index % 5 !== 0 ? groupIDs[index % groupIDs.length] : null;
    const city = groups.find((group) => group.id === groupID)?.city_or_region ?? cities[index % cities.length];
    const startsAt = new Date(Date.now() + (3 + (index * 7) % 300) * 24 * 60 * 60 * 1000).toISOString();
    const title = `${city} community meetup ${String(index + 1).padStart(3, "0")}`;
    const payload = groupID
      ? {
          event_group_id: groupID,
          event_title: title,
          event_description: eventDescription(index, city),
          event_area_label: `${city} centre`,
          event_starts_at: startsAt,
          event_capacity: 24 + (index % 5) * 12,
          event_venue_name: "Community cafe"
        }
      : {
          event_title: title,
          event_description: eventDescription(index, city),
          event_area_label: `${city} centre`,
          event_starts_at: startsAt,
          event_capacity: 24 + (index % 5) * 12,
          event_venue_name: "Community cafe"
        };
    return rpc(groupID ? "create_community_group_event" : "create_community_event", payload, ownerToken);
  });
  return [...existingEvents, ...created];
}

async function ensureComments(posts, profiles) {
  if (posts.length === 0 || profiles.length === 0) return 0;
  const existingComments = await getRows(
    "community_comments",
    `select=id,post_id,author_id,body,created_at&body=ilike.*norge360_comment_${seedVersion}*&order=created_at.asc`
  );
  const commentsToCreate = Math.max(0, counts.comments - existingComments.length);
  console.log(`${counts.comments} comment target; ${commentsToCreate} new comments needed.`);
  const comments = Array.from({ length: commentsToCreate }, (_, index) => {
    const post = posts[index % posts.length];
    let author = profiles[(index * 13 + 7) % profiles.length];
    if (author.user_id === post.author_id) author = profiles[(index * 13 + 8) % profiles.length];
    return {
      id: crypto.randomUUID(),
      post_id: post.id,
      author_id: author.user_id,
      body: seededComment(index, author),
      moderation_state: "active",
      created_at: new Date(Date.now() - index * 11 * 60 * 1000).toISOString()
    };
  });
  for (const batch of chunk(comments, 200)) {
    await rest("community_comments", {
      method: "POST",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify(batch)
    });
  }
  return comments.length;
}

async function verifySeed() {
  const [profiles, posts, groups, events, comments, media] = await Promise.all([
    getRows("community_profiles", "select=user_id&username=like.n360_*"),
    getRows("community_posts", "select=id&body=ilike.*norge360_seed*&order=created_at.asc"),
    getRows("community_groups", "select=id&slug=like.n360-demo-*"),
    getRows("community_events", `select=id&description=ilike.*norge360_event_${seedVersion}*`),
    getRows("community_comments", `select=id&body=ilike.*norge360_comment_${seedVersion}*`),
    getRows("community_post_media", `select=id&storage_path=like.seed-${seedVersion}/posts/*`)
  ]);
  return {
    profiles: profiles.length,
    posts: posts.length,
    groups: groups.length,
    events: events.length,
    comments: comments.length,
    postMedia: media.length
  };
}

async function main() {
  console.log(
    `Norge360 demo seed ${shouldApply ? "apply" : "preview"}: ${counts.profiles} users, ${counts.posts} posts, `
      + `${counts.groups} groups, ${counts.events} events, ${counts.comments} comments.`
  );
  console.log("Synthetic media ratio target: 86% of seeded posts.");
  if (!shouldApply) {
    console.log("Preview only. Add --apply to write to Supabase.");
    return;
  }
  if (!supabaseURL || !serviceRoleKey) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY for --apply.");
  }
  if (counts.profiles === 0) {
    throw new Error("At least one user is required because the seed owner creates groups and events.");
  }

  const assets = await loadAssets();
  await uploadBaseAssets(assets);
  const { profiles, authUsers } = await prepareProfiles();
  const ownerToken = await ownerSession(profiles[0], authUsers);
  const existingGroups = await getRows(
    "community_groups",
    "select=id,slug,created_by,city_or_region,photo_path&order=slug.asc"
  );
  const groups = await ensureGroups(ownerToken, existingGroups, profiles[0].user_id, assets);
  await ensureMemberships(groups, profiles);
  const posts = await ensurePosts(profiles, groups);
  await ensurePostMedia(posts, assets);
  await ensureEvents(ownerToken, groups);
  await ensureComments(posts, profiles);
  const result = await verifySeed();
  console.log("Done. Seed verification:", JSON.stringify(result));
  console.log("The generated accounts use @example.invalid addresses and are for development/staging only.");
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
