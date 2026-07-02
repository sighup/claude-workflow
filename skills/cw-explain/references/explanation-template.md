# Explanation Artifact Contract

The artifact is a single HTML file that a reader opens directly in a browser — offline, no server, no build step. Everything below is a requirement unless marked as guidance.

## Document Structure

- **One continuous page** — section headers and vertical scroll, never tabs.
- **Header**: change title, one-sentence summary, input mode and diff size (files/lines), date.
- **Table of contents**: anchor links to each section. Omit the Quiz entry when the quiz is skipped.
- **Four sections**, each with a stable `id` for TOC anchors: `id="background"`, `id="intuition"`, `id="code"`, `id="quiz"`.
- **Responsive**: readable on a phone. Max content width ~720-800px, fluid below that; diagrams scale with the viewport.
- **Self-contained**: all CSS in one `<style>` block, all JS in one `<script>` block, diagrams as inline SVG/HTML. Zero external requests — no CDN fonts, no image files, no `src`/`href` pointing at `http(s)://`.

## Section Contracts

### 1. Background

Teach the surrounding system before mentioning the diff. Two layers, in order:

- **Beginner layer**: what this part of the system is for, in plain language a newcomer to the codebase can follow.
- **Change-specific layer**: the specific components the diff touches, what they did *before* the change, and why that behavior needed to change.

When a spec/validation/review report was ingested, anchor this section to the stated requirements ("the spec calls for X; before this change the system did Y").

### 2. Intuition

The core essence of the change, taught through concreteness:

- Use **toy data and worked examples** — trace one small realistic input through the old behavior, then the new.
- Use **figures and diagrams liberally**. Diagrams are HTML/SVG, never ASCII art:
  - System/data-flow diagrams: boxes and arrows with the example data written on the arrows.
  - UI changes: simplified HTML mockups of the interface before/after.
- End with the one-paragraph "aha": what single idea, once grasped, makes the whole diff obvious.

### 3. Code

A high-level walkthrough, grouped in an order that makes sense to a human — by logical cluster (core change → supporting changes → tests/config), not by file path order.

- For each cluster: what it does, why it's there, then the key excerpt.
- Code excerpts in `<pre>` blocks with `white-space: pre` (or `pre-wrap` for long lines) so indentation survives. Keep excerpts short — the interesting hunk, not whole files.
- For very large diffs, walk representative files in depth and summarize the rest explicitly ("the remaining 12 files apply the same rename").

### 4. Quiz

Five multiple-choice questions, medium difficulty, testing **substantive understanding** of the change — the kind of thing a reviewer should know after reading the page. Never trivia ("what line number…") or gotchas.

Interactive behavior (embedded JS):

- Selecting an answer immediately reveals right/wrong plus a one-sentence explanation.
- Wrong answers show the explanation for why that choice is tempting but incorrect.
- No score submission, no persistence — it's a self-check.

## Callouts

Use styled callout boxes throughout (all sections) for:

- **Key concept** — a definition the reader needs before the next paragraph
- **Edge case** — behavior at a boundary the change handles (or deliberately doesn't)
- **Watch out** — a subtlety that would trip up someone modifying this code later

## Writing Style

Aim for the clarity and flow of Martin Kleppmann's technical writing: engaging, classic style, plain sentences, smooth transitions between sections. The reader should feel walked-through, not lectured. Serve beginners with the Background layer while keeping enough depth that a senior engineer unfamiliar with this subsystem still learns something.

## CSS Baseline (guidance)

System font stack, generous line-height (~1.6), muted palette with one accent color, visible focus states, distinct styling for callouts vs. prose vs. code. Dark-mode support via `prefers-color-scheme` is welcome but optional. Keep the total file lean — the value is the writing and diagrams, not decoration.

## Secret Hygiene

Before writing the file, scan the diff content being embedded for anything credential-shaped (keys, tokens, passwords, connection strings). Replace with `[REDACTED]` in the artifact and mention the redaction in the completion block.
