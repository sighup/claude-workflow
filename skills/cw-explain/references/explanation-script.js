/* ============================================================
   EXPLAINER TEMPLATE — CANONICAL SCRIPT
   Copy this file verbatim into the artifact's single script
   block, then:
     1. Replace the QUESTIONS array with the five real questions
        for this change (omit the whole quiz block, including its
        section markup, when quiz=off).
     2. Append any page-specific micro-interaction handlers below
        the TOC scroll-spy block (before/after toggles, step-
        through data flows) — keep them inline here, one script
        block total, per the self-containment rule.
   ============================================================ */

/* =========================================================
   QUIZ DATA
   Each question: prompt, options[], correct index, and a
   per-question explanation shown after answering. Five
   questions, medium difficulty, testing substantive
   understanding — never trivia or gotchas.
   ========================================================= */
const QUESTIONS = [
  // { q: "...", opts: ["...", "...", "...", "..."], correct: 0, why: "..." },
];

/* =========================================================
   RENDER + INTERACTION
   ========================================================= */

/* Authors tend to place the correct option in the same slot
   across every question (a known LLM bias — e.g. every answer
   is "B"). Shuffle each question's options at render time so
   the correct answer's on-screen position is unpredictable,
   regardless of how QUESTIONS was authored. */
function shuffledIndices(n) {
  const order = Array.from({ length: n }, (_, i) => i);
  for (let i = order.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [order[i], order[j]] = [order[j], order[i]];
  }
  return order;
}

const RENDERED = QUESTIONS.map((item) => {
  const order = shuffledIndices(item.opts.length);
  return {
    q: item.q,
    why: item.why,
    opts: order.map((i) => item.opts[i]),
    correct: order.indexOf(item.correct)
  };
});

const LETTERS = ["A", "B", "C", "D", "E"];
const quizEl = document.getElementById("quiz");
const answered = new Array(RENDERED.length).fill(false);
let correctCount = 0;

RENDERED.forEach((item, qi) => {
  const card = document.createElement("div");
  card.className = "q";

  const head = document.createElement("div");
  head.className = "qhead";
  head.innerHTML = `<span class="qnum">${qi + 1}</span><span class="qtext">${item.q}</span>`;
  card.appendChild(head);

  const opts = document.createElement("div");
  opts.className = "opts";

  item.opts.forEach((text, oi) => {
    const btn = document.createElement("button");
    btn.className = "opt";
    btn.innerHTML = `<span class="marker">${LETTERS[oi]}</span><span>${text}</span>`;
    btn.addEventListener("click", () => choose(qi, oi, card, opts, item));
    opts.appendChild(btn);
  });
  card.appendChild(opts);

  const fb = document.createElement("div");
  fb.className = "feedback";
  card.appendChild(fb);

  quizEl.appendChild(card);
});

function choose(qi, oi, card, opts, item) {
  if (answered[qi]) return;
  answered[qi] = true;

  const buttons = opts.querySelectorAll(".opt");
  buttons.forEach((b, i) => {
    b.disabled = true;
    if (i === item.correct) b.classList.add("correct");
    else if (i === oi) b.classList.add("wrong");
    else b.classList.add("muted");
  });

  const fb = card.querySelector(".feedback");
  const right = oi === item.correct;
  if (right) correctCount++;
  fb.classList.add("show", right ? "ok" : "no");
  fb.innerHTML = `<b>${right ? "Correct." : "Not quite."}</b> ${item.why}`;

  updateScore();
}

function updateScore() {
  const done = answered.filter(Boolean).length;
  const scoreEl = document.getElementById("score");
  if (done < RENDERED.length) {
    scoreEl.innerHTML = `Answered <b>${done}</b> of ${RENDERED.length}.`;
  } else {
    let note = correctCount === RENDERED.length
      ? "Every one — you've got this change cold."
      : correctCount >= 3
        ? "Solid grasp of the idea."
        : "Worth a re-read of the Intuition section.";
    scoreEl.innerHTML = `You scored <b>${correctCount} / ${RENDERED.length}</b>. ${note}`;
  }
}

/* =========================================================
   TOC SCROLL-SPY  +  mobile collapse
   ========================================================= */
const tocLinks = Array.from(document.querySelectorAll("nav.toc a"));
const targets = tocLinks
  .map(a => document.getElementById(a.getAttribute("href").slice(1)))
  .filter(Boolean);

const spy = new IntersectionObserver((entries) => {
  entries.forEach(e => {
    if (e.isIntersecting) {
      const id = e.target.id;
      tocLinks.forEach(a => a.classList.toggle("active", a.getAttribute("href") === "#" + id));
    }
  });
}, { rootMargin: "-10% 0px -75% 0px", threshold: 0 });
targets.forEach(t => spy.observe(t));

// mobile: tap "Contents" to toggle
const toc = document.getElementById("toc");
const label = toc.querySelector(".toc-label");
label.addEventListener("click", () => {
  if (window.matchMedia("(max-width: 880px)").matches) toc.classList.toggle("collapsed");
});
if (window.matchMedia("(max-width: 880px)").matches) toc.classList.add("collapsed");
