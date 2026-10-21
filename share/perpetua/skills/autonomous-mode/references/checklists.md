# Area checklists

Read the section that matches the work you are about to do. These are checks, not a script: apply what is relevant to the change, skip what is not.

## UX

You have the authority to make obvious UX decisions. For each feature, check:

- the user journey from start to finish;
- clarity of actions: the user always knows what a button or link will do;
- empty states;
- loading states;
- error messages: say what happened and what the user can do next;
- useful confirmations, especially before destructive actions;
- feedback after an action (success, failure, progress);
- consistent labels across the product;
- responsive behavior on mobile, tablet and desktop;
- keyboard accessibility: focus order, visible focus, no keyboard traps;
- forms: labels, required fields, sensible input types, preserved input on error;
- data validation, both client side for comfort and server side for correctness;
- network errors: timeouts, offline, retries, no silent failure;
- unexpected behavior: double submits, back button, refresh mid-flow, stale data.

When a behavior is technically correct but bad for the user, improve it. Do not sacrifice the user experience because the current implementation technically works.

## Security

Consider security on every change. Check in particular:

- authentication;
- authorization and role checks;
- data access: a user only reaches the data they are allowed to;
- input validation;
- injections (SQL, command, template, path traversal);
- XSS;
- CSRF where relevant;
- secrets and environment variables: never committed, never logged, never sent to the client;
- exposure of sensitive information in responses, errors and stack traces;
- direct API access that bypasses the interface;
- server-side security rules (database policies, row-level security, storage rules);
- uploads: type, size, storage location, execution;
- dependencies: known vulnerabilities, unnecessary new packages, install scripts;
- logs that contain personal or sensitive data.

A restriction applied only in the interface is never sufficient protection. Important permissions are enforced server side or at the appropriate layer of the architecture.

## SEO

For any relevant public page or content, take SEO into account without waiting to be asked. Check:

- `title`;
- meta description;
- canonical URL;
- heading hierarchy (one H1, then H2, H3);
- semantic HTML structure;
- indexable content (not hidden behind client-only rendering when it must be indexed);
- clean URLs;
- internal links and meaningful anchor text;
- `alt` text on images;
- Open Graph tags;
- Schema.org structured data where relevant;
- sitemap;
- `robots.txt`;
- pagination;
- duplicate pages;
- performance and Core Web Vitals;
- rendering that allows indexing when needed.

No artificial SEO changes and no keyword stuffing.
