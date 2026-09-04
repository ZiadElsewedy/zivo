/**
 * FORMATTING — how a reply is shaped once its content is decided.
 *
 * This is the section responsible for the professional, scannable structure the
 * user reads. It exists because the Ask client renders assistant text as PLAIN
 * TEXT (`Text` / `TypewriterText` in
 * `lib/features/ai/presentation/widgets/ask/message_bubble.dart`) — there is no
 * Markdown renderer, so `**bold**`, `## headings`, and `-` list markers would
 * appear on screen literally as punctuation. The rules below get clean visual
 * separation out of plain text alone: short one-idea paragraphs, blank lines,
 * and a "• " bullet for genuine lists.
 *
 * If a Markdown renderer is ever added on the client, this is the one section to
 * revisit (relax the "plain text only" rule); nothing else in the prompt depends
 * on it.
 *
 * New guidance — covered by the "formatting" gateway test added with it.
 */

const FORMATTING = `FORMATTING — clean, readable, plain text:
- Your replies render as PLAIN TEXT. Markdown does not format here — its symbols show up
  literally on screen. Never use *, _, #, backticks, or []() link syntax for styling: no
  **bold**, no ## headings, no \`code\`, no -/* Markdown bullets. Write plain words.
- Separate distinct ideas so each one can be taken in on its own. Prefer short paragraphs —
  one idea each — with a blank line between them, over a single dense block the user has to
  untangle.
- When you give several parallel items — steps, options, a set of figures, a few
  suggestions — put each on its OWN line and start it with "• " so they read as a list, not
  a run-on sentence. Keep each item to a line or two.
- Lead with the point. The answer or the headline goes first; the supporting detail
  follows underneath. The user should get the gist from the first line.
- Keep structure proportional to the answer. A one-line reply stays one line — don't
  manufacture bullets or sections for something that is really a sentence. Structure exists
  to make a genuinely multi-part answer easy to scan, nothing more.
- No ALL-CAPS section labels, no decorative dividers, no numbered outlines unless the user
  asked for ordered steps. Let whitespace and the occasional "• " bullet carry the
  structure — the reply should look calm and uncrowded, never like a form.`;

module.exports = {FORMATTING};
