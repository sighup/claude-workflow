# External Context Protocol

Rules for classifying, processing, and attributing external context sources in cw-research.

## Source Classification

For each source the user provides, classify it and process accordingly:

| Source Type | Detection | Processing |
|-------------|-----------|------------|
| Web URL | Starts with `http://` or `https://` | Fetch with `WebFetch` |
| GitHub URL | Contains `github.com` | Fetch with `WebFetch` or use `Bash` with `gh` CLI for issues/PRs |
| Local file | Starts with `/`, `./`, `../`, or `~` | Read with `Read` tool |
| Local directory | Path ending with `/` or detected as directory | Explore with `Glob` and `Read` |
| Image file | Extensions: `.png`, `.jpg`, `.jpeg`, `.gif`, `.svg`, `.webp` | Read with `Read` tool (multimodal), describe content in report |
| Search query | Does not match URL or path patterns | Search with `WebSearch` |

## Graceful Error Handling

When a source cannot be accessed, do NOT fail or halt the research process. Instead, note it in the report and continue:

```markdown
### External Context: {source description}
> Source: {URL or path}
> Status: Inaccessible -- {reason}

Could not access this source. {Specific reason, e.g.:
- "Authentication required -- WebFetch cannot access pages behind login"
- "404 Not Found -- the URL may have moved or been deleted"
- "File not found -- the path does not exist in the current filesystem"
- "Connection timeout -- the server did not respond"}

If this source contains important context, consider:
- Providing the content directly by pasting it into the conversation
- Sharing a publicly accessible version of the document
- Summarizing the key points manually
```

**Important:** Warn the user upfront if any provided URLs appear to require authentication (e.g., Jira, Confluence, private GitHub repos). WebFetch cannot access authenticated pages. Suggest alternatives:
- Use `gh` CLI for GitHub resources (if authenticated locally)
- Paste relevant content directly
- Provide exported/downloaded files instead

## Source Attribution Rules

- Every piece of information from an external source MUST be attributed with `> Source: {identifier}`
- Codebase findings and external context must be clearly distinguishable
- Do not mix external information into dimension sections without attribution
- If external context contradicts codebase findings, note both perspectives

## External Context Storage

Keep all processed external context in memory for incorporation into the report. For each source, retain:
- Source identifier (URL, path, or description)
- Source type (web, file, image, search)
- Extracted content or summary
- Access status (accessible, inaccessible, partial)

## Report Integration Format

If external context sources were provided, add an "External Context" section to the report:

```markdown
## External Context

{Overview of external sources consulted and their relevance to the research topic.}

### {Source 1 Title or Description}
> Source: {URL or file path}
> Type: {web | file | image | search}

{Summary of relevant information extracted from this source.
Focus on how it relates to the codebase findings above.
Include specific details that would help a developer understand
the broader context around this feature or area.}

### {Source 2 Title or Description}
> Source: {URL or file path}
> Type: {web | file | image | search}

{Summary of relevant information from this source.}

### Inaccessible Sources

{List any sources that could not be accessed, with reasons.
Only include this subsection if there were inaccessible sources.}

| Source | Reason |
|--------|--------|
| {URL or path} | {Authentication required / Not found / Timeout / etc.} |
```
