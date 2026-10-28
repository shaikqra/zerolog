# ZeroLog landing page

Three static pages and one stylesheet. No build step, no dependencies, no cookies.

| File | What it is |
|---|---|
| `index.html` | The landing page |
| `thanks.html` | Shown after someone joins the waitlist; carries the Founding Member offer |
| `privacy.html` | Short privacy notice (**draft**) |
| `styles.css` | All styling, shared by the three pages |

## Preview it locally
From this folder, run `python -m http.server 8080`, then open http://localhost:8080.
The waitlist form only jumps to the thank-you page. **It does not save any emails yet.**

## Launch-day checklist (Nov 10): every placeholder to replace
- [ ] **Waitlist form** (`index.html`, both forms + the `<script>` block): replace with the Kit form embed or point `action` at Kit, and set Kit's redirect to `thanks.html`.
- [ ] **Checkout button** (`thanks.html`, `data-checkout`): replace `href="#"` with the Lemon Squeezy checkout link. Do a test purchase **and** a test refund.
- [ ] **Concept video** (`index.html`, `.video-frame`): replace the placeholder text with `<video src="demo.mp4" controls playsinline muted poster="poster.jpg"></video>`. Keep the "Concept demo" caption.
- [ ] **Contact email** `hello@getzerolog.com`: set up email forwarding once the domain is bought (Cloudflare Email Routing is free).
- [ ] **Privacy notice**: review it, then remove the draft banner.
- [ ] **Analytics**: add the Cloudflare Web Analytics snippet to all three pages.
- [ ] **Domain**: run the USPTO + UKIPO checks first, then buy `getzerolog.com`.
