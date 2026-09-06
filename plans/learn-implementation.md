# Learn: course and resource library plan

Status: proposal for discussion. No application changes made.

This plan builds on [the curriculum outline](learn.md). That outline remains the long-term content map; this document defines how to deliver it in the product.

## Current direction: start with the movie-making workflow

Start with a supplied 30-second script and teach the workflow supported by the app:

1. Turn the script into a shot list.
2. Define the assets needed for each shot.
3. Generate and review those assets, introducing tool choices where needed.

Editing the assets into a finished film follows this workflow. Creating a story with an LLM is a separate guide for learners who need help developing a script.

The immediate increment is [Script to Shot List](learn-script-to-shot-list.md): a small lesson brief with an example script, worked shot list, and learner exercise. Review this teaching example before producing the asset-planning lesson or application UI.

This direction supersedes the earlier proposed opening sequence and three-resource preview below. The full curriculum and page-building breakdown remain a backlog to revise as these first lessons take shape, not the immediate implementation scope.

## Product direction

Build one public learning library with two ways in:

- **Take a course:** follow an ordered path toward a finished film.
- **Explore resources:** find help with a specific filmmaking task, without joining a course.

A course organizes shared resources; it does not own separate copies of their content. Someone searching for motion prompts should land on the same resource a student reads during the video-generation module.

Proposed launch assumptions:

- Learning content and courses are accessible without signing in or paying.
- Launch on the web. People can use their preferred filmmaking tools; the native app is optional.
- Start with written lessons and visual examples, with short demonstrations where they help. The final media mix is open for discussion.
- Teach through making one small film, with a concrete output at each stage.
- Prioritize a complete beginner course over launching three partially written courses.

## Learning experience

### Learn landing page

Replace the empty `/learn` page with:

1. A clear invitation to make a first film, with a primary link to the beginner course.
2. Two visible entry points: **Take a course** and **Explore resources**.
3. The available course, its finished-film example, prerequisites, and realistic effort expectations.
4. Resources grouped by filmmaking topic, plus links to tool guides and workflows.

Use the topic and format lists in the original outline as metadata, not five competing navigation systems. Tool recommendations and workflow recommendations are curated views of the library. Only show categories with published content. Keep the longer courses in the roadmap until they have useful material.

### Course overview

“Your First 30-Second Film” explains what the learner will make, shows the example film, lists the required capabilities/tools, and presents the ordered modules. Every lesson is accessible immediately; completion never gates the next lesson.

Each module identifies its practical output. Include a start/resume action and a simple progress indicator when progress tracking is introduced.

### Shared resource page

Every resource works on its own and includes:

- A clear title, summary, intended outcome, level, and estimated reading/practice time.
- Necessary context or prerequisite links without assuming earlier course attendance.
- The explanation, annotated examples or demonstrations, and actionable steps.
- Common mistakes, an exercise or checklist where appropriate, and related resources.
- An updated date; tool-dependent material also records when it was last verified.

When opened from a course, the same page adds course context: module position, previous/next steps, and the assignment for the learner's film. When opened independently, it offers relevant courses without forcing enrollment. Keep course-specific instructions outside the shared article body.

For example, **Writing Image Prompts** teaches the general technique. Within the beginner course, its assignment is to write prompts for the learner's three to five planned shots. A later course can reuse it with a different assignment or link to it as optional review.

### Resource library

Provide title/summary search and filters for topic, format, and level. Use shareable URL parameters and a useful empty state with a clear reset action. Add tool-specific filtering only when the catalog is large enough to need it.

Initially support lessons, tool guides, and workflow walkthroughs. The content model can accommodate film breakdowns and challenges as they are authored; every format does not need a separate launch section.

## First course: Your First 30-Second Film

Keep the ten modules from the outline, with two focused resources per module. Target a simple film with three to five shots, one consistent style, and music/atmosphere; dialogue is optional and outside the core assignment.

| Module | Shared resources from the outline | Output for the learner's film |
| --- | --- | --- |
| 1. Recommended Starter Toolkit | Image and Video Tools; Editing and Audio Tools | A chosen setup and a small generation budget |
| 2. Your First Film Workflow | From Idea to Shot List; From Generated Clips to Final Cut | A production checklist and understanding of the full process |
| 3. Ideas and Premises | One-Sentence Stories; Beginnings, Middles, and Endings | A one-sentence premise and three story beats |
| 4. Visual Style | Moodboards and References; Color, Lighting, and Texture | A small reference board and style description |
| 5. Shot Planning | Shot Sizes and Composition; Three-Shot Stories | A three-to-five-shot plan |
| 6. Image Generation | Writing Image Prompts; Selecting and Refining Images | Selected still images for the planned shots |
| 7. Image-to-Video | Motion Prompts; Choosing Usable Takes | Selected video takes |
| 8. Basic Editing | Assembling a Timeline; Trimming and Transitions | A watchable rough cut |
| 9. Music and Sound | Choosing Music; Adding Atmosphere | A cut with intentional sound |
| 10. Exporting and Sharing | Aspect Ratios and Export Settings; Your First Film Screening | An exported film and self-review |

The early workflow module is an orientation, not a requirement to produce the film before learning the individual skills. Link to the detailed resources instead of duplicating them.

Use one worked example throughout: finished film, premise, style references, shot list, prompts, selected/rejected takes, rough cut, and final export. Provide reusable shot-list and review templates. A screening can be a private watch-through or sharing with someone the learner chooses; publishing is optional.

Completion rubric: the story is understandable, shots feel intentionally connected, sound supports the film, and the export plays correctly. Finishing and reviewing the film matters more than checking off reading.

## Shared content model

| Entity | Purpose | Key fields |
| --- | --- | --- |
| Resource | One independently useful piece of content | Stable ID, slug, title, summary, format, topics, level, body, media/downloads, prerequisites, related IDs, estimated time, publication state, updated/verified dates |
| Course | An ordered path toward a result | Stable ID, slug, title, summary, outcome, prerequisites, example film, publication state, ordered modules |
| Course module | A stage with a practical output | Stable ID, title, introduction, outcome, ordered steps |
| Course step | Reuses a resource in context | Stable ID, resource ID, required/optional status, course-specific assignment |
| Progress, later | Records a learner's position and completed work | Course ID, completed step IDs, last visited step, timestamps |

Course order and assignments live in the course definition. Topic/format groupings derive from resource metadata. Do not duplicate articles for each course or category. Track course-step completion separately so reading a reused resource does not automatically finish a different course's assignment.

## Web implementation approach

The existing app has a Learn navigation link and an empty `apps/web/app/learn/page.tsx`. It already includes Markdown rendering dependencies, Clerk, and S3-backed project content.

Proposed routes:

- `/learn`: landing page.
- `/learn/courses/[courseSlug]`: course overview and syllabus.
- `/learn/resources`: searchable/filterable library.
- `/learn/resources/[resourceSlug]`: canonical resource page.
- `/learn/resources/[resourceSlug]?course=[courseSlug]&step=[stepId]`: the same resource with course navigation and assignment.

Validate that the requested step belongs to the requested course and references the current resource. Ignore invalid context and show the standalone resource. Canonical metadata points to the resource URL without course parameters.

Start with repository-managed Markdown resources and typed course/catalog metadata under `apps/web/content/learn`, with a loader and validation under `apps/web/lib/learn`. Choose the exact file layout during implementation. Reuse the existing Markdown stack where appropriate; a new CMS or LMS is not needed for the first release. Store large media in the existing asset infrastructure with stable public delivery URLs, subject to verifying its configuration.

Keep curated educational content separate from the existing project-associated posts. Render learning pages publicly, and keep authentication out of the reading path. Before coding, read the installed Next.js guides required by `apps/web/AGENTS.md`.

## Progress and connection to filmmaking

First establish the course/resource experience without requiring accounts or enrollment. Then add explicit “Mark complete” and “Continue course” controls, saving progress locally in the browser. Explain that local progress is device/browser-specific; browsing still works if storage is unavailable. Completion can be undone, and optional steps do not affect the required-step total.

Account-synced progress is a later feature using Clerk identity and a storage design chosen for user-specific updates. Do not assume the existing project JSON persistence is sufficient for concurrent progress writes.

After the learning flow works, offer an optional “Create a film project” action using the existing project creation flow. Carry over a learner's course context only when supported and authorized by their action. Keep all exercises usable with downloadable templates and external tools. Native-app links and deeper project automation come later.

## Delivery phases

### 1. Prove the shared-resource experience

Build this as the following small increments, in order. Each increment produces something concrete to review before moving on; these are work boundaries, not mandatory approval gates. Keep the work in local/deployment preview until phase 2 is ready to publish.

#### 1.1 Define one sample learning journey

Start with the [Script to Shot List brief](learn-script-to-shot-list.md), before building pages:

- Supply a simple 30-second script so writing a story is not a prerequisite.
- Explain how to turn its story beats into individual shots.
- Provide a worked shot list and a short learner exercise.
- Stop at the shot list. Asset requirements and generation are subsequent increments.
- Keep the explanation useful independently; the course assignment applies it to the supplied script or the learner's own script.

**Deliverable:** one lesson brief containing a script, worked shot list, reasoning, and course assignment.

**Done when:** a learner can explain why each shot is needed and produce a shot list ready for asset planning.

#### 1.2 Write one complete resource and its course assignment

Use **Three-Shot Stories** to establish the editorial template:

- Write the standalone explanation, a worked example, common mistakes, and a short exercise.
- Include a simple annotated shot sequence; a complete generated film is unnecessary for this increment.
- Write the course assignment separately: turn the learner's premise into a three-shot plan.
- List prerequisite context, related resources, and any example assets needed. Do not create links to pages that do not exist yet.

**Deliverable:** one reviewable Markdown article plus its separate course assignment.

**Done when:** the article makes sense on its own, and the assignment clearly applies it to a continuing film project. Use this real content to guide the schema and layout.

#### 1.3 Establish the minimum content structure

- Define resource metadata and course/module/step records using the fields needed by the sample.
- Store the article body once and reference its stable resource ID from a course step.
- Add the content loader and validation for duplicate IDs/slugs, missing metadata, broken references, and publication state.
- Define explicit preview behavior: drafts are available only in the intended preview environment and absent from public listings and direct production routes. A `noindex` tag alone does not enforce this distinction.
- Document how to add a resource and insert it into a course. Leave progress storage and unused content formats for later.

**Deliverable:** the sample resource and course assignment load as validated content, with a short authoring guide.

**Done when:** a course step resolves to the original article, and an invalid reference produces an actionable validation error rather than a broken page.

#### 1.4 Build the standalone resource page

- Implement `/learn/resources/[resourceSlug]` using the completed article.
- Render its title, summary, outcome, reading/practice estimate, body, examples, and exercise.
- Establish readable typography, mobile spacing, accessible media, and a return-to-library link once the library exists.
- Handle missing/unpublished resources and provide canonical metadata for the standalone URL.

**Deliverable:** one real lesson that can be read directly by a signed-out visitor in preview.

**Done when:** the resource works without course parameters, account state, or assumed prior lessons. Review this page's content and layout before multiplying it across the catalog.

#### 1.5 Add course context to that same page

- Create the beginner-course preview definition with the sample step in its intended module.
- Resolve `course` and `step` parameters against the loaded resource.
- Add the course name, module position, and separate “For your film” assignment.
- Link back to the course overview when available. Show previous/next controls only when the corresponding sample steps exist.
- Fall back to the standalone presentation for invalid context and retain the standalone canonical URL.

**Deliverable:** two links to the same resource—one standalone and one with a course assignment.

**Done when:** changing the article changes both views, while changing the course assignment leaves the standalone article unchanged.

#### 1.6 Complete the three-resource sample

- Author **From Idea to Shot List** and **Writing Image Prompts** using the established template.
- Carry the same teaching example through all three resources, with a worked shot list and example prompts.
- Supply enough context for each article to stand alone, while course assignments build on the learner's previous output.
- Connect the three available course steps in order and add relevant standalone resource links.
- Clearly end the sample after image prompts; do not suggest the learner has completed a film or the full course.

**Deliverable:** a working sequence from story outline to shot plan to image prompts.

**Done when:** someone can follow the sample without dead ends or missing required material, and can also start at any resource independently.

#### 1.7 Build the course overview

- Implement `/learn/courses/[courseSlug]` with the course promise, prerequisites, and intended film outcome.
- Present the available sample within the planned module structure, clearly labeled as a preview.
- Link only available lessons; any roadmap modules are plain text rather than broken lesson links.
- Add “Start preview” and direct lesson links. Reserve resume/progress controls for phase 3.

**Deliverable:** a course entry page that leads into the three-resource sample.

**Done when:** a visitor understands the full course's goal, what the preview currently covers, and where to begin.

#### 1.8 Build the basic resource library

- Implement `/learn/resources` with the three resources, showing title, summary, topic, and format.
- Link each card to its standalone resource URL, without carrying course context.
- Derive the listing from resource metadata, rather than maintaining a second hand-written catalog.
- Keep search and interactive filters in phase 2; three resources only need a clear browsable list.

**Deliverable:** an independent entry point to all three sample resources.

**Done when:** someone can find and read a resource without visiting a course page, and adding a visible resource updates the listing automatically.

#### 1.9 Assemble the Learn landing page and navigation

- Replace the empty `/learn` page with the two entry points: **Take a course** and **Explore resources**.
- Feature the beginner-course preview and the available resources using existing catalog data.
- Add a usable mobile Learn navigation entry alongside the existing desktop link.
- Avoid empty topic sections or promotional claims about a finished course/example film that is not available yet.

**Deliverable:** a complete preview journey beginning at the site's Learn navigation.

**Done when:** both paths are obvious and usable on desktop, mobile, and keyboard navigation.

#### 1.10 Verify the complete preview

- Walk through: Learn → course overview → sample steps → end of sample.
- Walk through: Learn → resource library → standalone resource → associated course.
- Check direct URLs, refreshes, invalid course context, missing resources, and production draft exclusion.
- Edit one article and verify both presentations update; edit one assignment and verify only the course presentation changes.
- Run the implementation checks and browser verification listed below, with focused validation tests for content references and course-context resolution.
- Record remaining content/design issues and the phase 2 authoring backlog.

**Deliverable:** a reviewed preview with three real resources and a clear list of remaining launch work.

**Done when:** both learning journeys work, resource bodies are stored once, and there is a repeatable process for authoring the rest of the course.

The first implementation task is **1.1 only: the sample learning brief**. It should be small enough to discuss the actual teaching approach before committing to page designs or building the full catalog.

### 2. Publish a complete beginner experience

- Author and review the full ten-module/twenty-resource beginner curriculum.
- Produce the worked example film and supporting artifacts, including unsuccessful takes with explanations.
- Verify current tool instructions, available alternatives, costs, and usage terms before publication; record verification dates without promising future pricing or availability.
- Add search/filters, metadata, sitemap inclusion, and responsive accessible navigation.
- Check every lesson can be followed independently and every assignment advances the same film.

Done when a new learner can go from no film to an exported 30-second film using the published material, with no placeholder lessons or required unpublished links.

### 3. Add continuity for returning learners

- Add local progress, resume, and reversible completion controls.
- Add optional entry into the existing film-project creation flow.
- Observe where learners get stuck and revise instructions/examples before expanding the curriculum.

### 4. Expand the catalog

- Build “Your First 2-Minute Film,” reusing fundamentals and adding consistency, dialogue, coverage, and revision material.
- Follow with “Your First 10-Minute+ Film,” focused on production planning and sustained narrative.
- Expand breakdowns, challenges, tool comparisons, and workflow collections as real resources become available.
- Consider account sync and editorial tooling when usage and publishing needs justify them.

## Verification and success criteria

- Content validation catches duplicate IDs/slugs, missing required metadata, invalid course references, and published content pointing to required drafts.
- A signed-out visitor can open every published course and resource directly.
- The same resource works with no course context, valid course context, and invalid/stale context.
- Required course steps have a continuous path; optional readings do not derail next-step navigation.
- Search and filters work together, support direct links, and handle no matches.
- Keyboard and mobile users can access Learn, the syllabus, resource filters, and course navigation. The current header hides its navigation on smaller screens, so launch needs a mobile Learn entry point.
- Media has appropriate captions/transcripts or alt text, and downloads/links are checked.
- When progress is added, verify refresh/resume, undo, unavailable storage, and changed curricula using stable step IDs.
- Run `pnpm lint`, `pnpm typecheck`, and `pnpm build` for implementation changes, plus browser verification of both learning journeys.

Primary product signal: can a beginner finish a film? Supporting signals include course starts, movement between stages, self-reported completion, and whether a library visitor finds a useful next action. Reading a page is not evidence that someone completed an exercise.

## Decisions to revisit before production content

- Written/visual/video mix and who will produce the demonstration assets.
- The subject and style of the example film.
- The tested starter tool setup and intended budget, without making one vendor a prerequisite for the general lessons.

Payments, certificates, graded submissions, discussion systems, and a CMS are outside the proposed first release.
