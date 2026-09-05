import assert from "node:assert/strict";
import { registerHooks } from "node:module";
import test from "node:test";

// Exercise the real server actions and access helpers with isolated auth and storage.
const state = { user: { id: "user-1", username: "owner" }, projects: new Map(), invalidated: [] };
globalThis.__projectActionTest = state;
const modules = {
  "@clerk/nextjs/server": `export async function currentUser() { return globalThis.__projectActionTest.user; } export async function auth() { return { userId: globalThis.__projectActionTest.user?.id }; }`,
  "next/cache": `export function revalidatePath(path) { globalThis.__projectActionTest.invalidated.push(path); }`,
  "next/navigation": `export function notFound() { throw new Error("NOT_FOUND"); } export function redirect(path) { throw new Error("REDIRECT:" + path); }`,
  "@/lib/projects": `export async function getProject(id) { return globalThis.__projectActionTest.projects.get(id) || null; } export async function saveProject(id, data) { globalThis.__projectActionTest.projects.set(id, structuredClone(data)); } export async function deleteProject(id) { globalThis.__projectActionTest.projects.delete(id); } export async function getProjectByUsernameAndSlug(username, slug) { for (const [id, project] of globalThis.__projectActionTest.projects) { if (project.username === username && project.slug === slug) return { id, project }; } return null; }`,
  "@/lib/s3": `export function deleteObjectFromS3() {} export function getFileBufferFromS3() {} export function putObjectToS3() {} export function uploadFileFromBuffer() {}`,
};
const hooks = registerHooks({
  resolve(specifier, context, nextResolve) {
    if (modules[specifier])
      return {
        url: `data:text/javascript,${encodeURIComponent(modules[specifier])}`,
        shortCircuit: true,
      };
    if (specifier === "@/lib/project-basics")
      return { url: new URL("../lib/project-basics.ts", import.meta.url).href, shortCircuit: true };
    return nextResolve(specifier, context);
  },
});
const { saveProjectBasics } = await import("../lib/actions/projects.ts");
const { getVisibleProject, getOwnedProject } = await import("../lib/project-access.ts");

test("create → update → share → unshare preserves data and enforces ownership", async () => {
  const first = await saveProjectBasics({ title: "A film", logline: "" });
  const second = await saveProjectBasics({ title: "A film", logline: "" });
  assert.notEqual(first.projectId, second.projectId);
  const draft = state.projects.get(first.projectId);
  assert.equal(draft.username, "owner");
  assert.equal(draft.isPublished, false);
  assert.notEqual(draft.slug, state.projects.get(second.projectId).slug);
  draft.screenplayElements = [{ id: "element", content: "Keep this screenplay" }];
  draft.scenes = [{ id: "scene", promptShots: [{ id: "shot", prompt: "Keep this prompt" }] }];
  draft.customData = { keep: "future fields" };
  const slug = draft.slug;
  await saveProjectBasics(
    {
      title: "Renamed film",
      logline: "A film about light",
      isPublished: true,
      filmLink: "https://vimeo.com/123",
    },
    first.projectId
  );
  const published = state.projects.get(first.projectId);
  assert.equal(published.slug, slug);
  assert.deepEqual(published.screenplayElements, draft.screenplayElements);
  assert.deepEqual(published.scenes, draft.scenes);
  assert.deepEqual(published.customData, draft.customData);
  assert.ok(state.invalidated.includes(`/owner/${slug}`));
  assert.ok(state.invalidated.includes("/projects"));
  assert.ok(state.invalidated.includes("/films"));

  state.user = null;
  assert.equal((await getVisibleProject("owner", slug)).project.title, "Renamed film");
  await assert.rejects(saveProjectBasics({ title: "Unauthorized" }, first.projectId));
  await assert.rejects(getOwnedProject(first.projectId), /NOT_FOUND/);

  state.user = { id: "other-user", username: "other" };
  await assert.rejects(saveProjectBasics({ title: "Unauthorized" }, first.projectId), /permission/);
  await assert.rejects(getOwnedProject(first.projectId), /NOT_FOUND/);

  state.user = { id: "user-1", username: "owner" };
  await saveProjectBasics(
    { title: "Renamed film", logline: "", isPublished: false },
    first.projectId
  );
  assert.equal((await getOwnedProject(first.projectId)).title, "Renamed film");
  assert.ok(await getVisibleProject("owner", slug));
  state.user = null;
  assert.equal(await getVisibleProject("owner", slug), null);
  state.user = { id: "other-user", username: "other" };
  assert.equal(await getVisibleProject("owner", slug), null);
  assert.equal(await getVisibleProject("owner", "missing"), null);
  hooks.deregister();
});
