import assert from "node:assert/strict";
import test from "node:test";
import { applyProjectBasics, getFilmEmbedUrl, getFilmUrl } from "../lib/project-basics.ts";

const original = {
  title: "Old title",
  logline: "Old description",
  duration: "5 minutes",
  genre: "Drama",
  username: "filmmaker",
  slug: "original-url",
  thumbnail: "old.jpg",
  filmLink: "https://vimeo.com/123",
  links: { links: [{ label: "Reference", url: "https://example.com" }] },
  tools: [{ name: "Blender", category: "other" }],
  screenplayText: "INT. STUDIO - DAY",
  screenplayElements: [{ id: "element", type: "action", content: "A film begins." }],
  characters: [{ name: "Sam", appearance: "Red coat", images: ["sam.jpg"] }],
  scenes: [{ id: "scene", promptShots: [{ id: "shot", prompt: "A studio" }] }],
  development: { conceptSeed: "An idea" },
  phaseVisibility: { screenplay: "published" },
  futureField: { keep: true },
  isPublished: true,
  publishedAt: "2026-01-01T00:00:00Z",
};

test("saving basics preserves all working material, identity, and unknown fields", () => {
  const updated = applyProjectBasics(original, {
    title: " New title ",
    logline: " A film. ",
    thumbnail: "",
    filmLink: "",
    isPublished: false,
    username: "attacker",
    scenes: [],
  });
  assert.equal(updated.title, "New title");
  assert.equal(updated.logline, "A film.");
  assert.equal(updated.isPublished, false);
  assert.equal(updated.thumbnail, "");
  assert.equal(updated.filmLink, "");
  for (const field of [
    "username",
    "slug",
    "screenplayText",
    "screenplayElements",
    "characters",
    "scenes",
    "development",
    "phaseVisibility",
    "tools",
    "links",
    "futureField",
    "publishedAt",
  ])
    assert.deepEqual(updated[field], original[field]);
  assert.equal(original.title, "Old title");
});

test("a title alone is sufficient and publishing does not require phases or a film", () => {
  const draft = applyProjectBasics(
    { title: "", logline: "", duration: "", genre: "", tools: [], links: { links: [] } },
    { title: "First film" }
  );
  assert.equal(draft.isPublished, false);
  assert.equal(draft.filmLink, "");
  const shared = applyProjectBasics(draft, { title: draft.title, isPublished: true });
  assert.ok(shared.publishedAt);
  assert.equal(shared.isPublished, true);
});

test("invalid titles and unsafe film links are rejected", () => {
  for (const title of ["", "  ", "x".repeat(201)])
    assert.throws(() => applyProjectBasics(original, { title }));
  for (const filmLink of [
    "javascript:alert(1)",
    "data:text/html,test",
    "ftp://example.com",
    "not a URL",
    "https://user:password@example.com",
  ]) {
    assert.equal(getFilmUrl(filmLink), null);
    assert.throws(() => applyProjectBasics(original, { title: "Film", filmLink }));
  }
});

test("YouTube, Vimeo and unlisted Vimeo links embed only on trusted hosts", () => {
  for (const url of [
    "https://youtu.be/dQw4w9WgXcQ",
    "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
    "https://youtube.com/shorts/dQw4w9WgXcQ",
  ])
    assert.equal(getFilmEmbedUrl(url), "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ");
  assert.equal(
    getFilmEmbedUrl("https://vimeo.com/123456789/abc123"),
    "https://player.vimeo.com/video/123456789?h=abc123"
  );
  assert.equal(
    getFilmEmbedUrl("https://player.vimeo.com/video/123456789?h=abc123"),
    "https://player.vimeo.com/video/123456789?h=abc123"
  );
  for (const url of [
    "https://youtube.com.evil.test/watch?v=dQw4w9WgXcQ",
    "https://vimeo.com.evil.test/123",
    "https://youtube.com/watch?v=invalid",
    "https://example.com/movie.mp4",
  ])
    assert.equal(getFilmEmbedUrl(url), null);
  assert.equal(getFilmUrl("https://example.com/movie.mp4"), "https://example.com/movie.mp4");
});
