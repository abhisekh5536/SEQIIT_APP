# Saqiit — Facilities Module Implementation Plan

This sits in the roadmap as a **Phase 5 (🟠) feature**, alongside Parking/Marketplace/Delivery Management. It does **not** require Master Admin Panel changes beyond one new `ModuleFlag` entry, since that toggle system already exists.

## Scope decision

This module is built as **Option A — a display/catalog module**: Society Admin adds facilities (image, description, hours, rules), residents browse them on the User Panel. It is deliberately **not** a booking/reservation system — that stays a separate future module (**Facility Booking**, already listed in the roadmap).

The schema and detail-page layout below are designed so Facility Booking can slot in later (a "Book Now" button, slot calendar, per-use pricing) without redesigning this module — but none of that logic is built now. Keep this boundary firm during implementation to avoid scope creep.

## Where it plugs into what you have

Same conventions as the Marketplace module, reused deliberately so components/patterns carry over:

| Concern | Approach (matches Marketplace) |
|---|---|
| Society scoping | `Facility.society_id` — every list/detail query filtered server-side from the JWT session, never a client-passed ID |
| Module on/off per society | `ModuleFlag` (module_key = `facilities`) |
| Multi-image support | Separate `FacilityImage` table with `sort_order`, same pattern as `MarketplaceImage` |
| Admin-managed master list | Facility categories follow the same "addable, not hardcoded" pattern as Marketplace categories |
| Auth/session | Existing JWT session from Society Admin login (create/edit) and User Panel login (view) |

## Database Schema

```
Facility
  id, society_id (FK), name, description, category_id (FK),
  status (active | maintenance | closed),
  operating_hours (text, e.g. "5:00 AM – 10:00 PM" or structured per-day if needed later),
  rules_text (nullable — guidelines, occupancy limits, guest policy, etc.),
  created_at, updated_at

FacilityImage
  id, facility_id (FK), image_url, sort_order

FacilityCategory
  id, name (e.g. "Sports", "Wellness", "Community Hall", "Outdoor")
  -- global list, same pattern as ModuleFlag/MarketplaceCategory; admin-editable, not hardcoded
```

Notes:
- `status` matters more than it looks — facilities go down for maintenance/cleaning regularly, and residents seeing a facility with no indication it's closed is a common complaint in these apps. Don't ship without this field.
- `operating_hours` as plain text is fine for v1. If a society later wants per-day timings (e.g., pool closed Mondays), that's a structured-hours upgrade, not a v1 requirement.
- No pricing, no slot/calendar tables, no booking-status fields — intentionally out of scope here.

## Screens

**Society Admin Panel**
1. **Facilities List** — table of all facilities for the society, with status badges (active/maintenance/closed), quick edit/disable
2. **Add/Edit Facility** — name, description, category, images (multi-upload), operating hours, rules text, status
3. **Facility Categories** — manage the master category list (admin-editable, same pattern as other master lists)
4. **Facilities Settings** — enable/disable the module for the society (reflects `ModuleFlag`)

**User Panel**
5. **Facilities Page** — grid/list of the society's active facilities, filterable by category; facilities under maintenance/closed shown with a clear status badge rather than hidden (so residents aren't confused why something vanished)
6. **Facility Detail** — full image gallery, description, operating hours, rules, status; includes a disabled/stubbed "Book Now" button so the Facility Booking module can attach here later without a redesign

## API Endpoints

```
GET    /societies/:id/facilities                  (scoped by session's society automatically)
POST   /societies/:id/facilities                  (admin)
GET    /facilities/:id
PATCH  /facilities/:id                             (admin)
PATCH  /facilities/:id/status                       (admin — active/maintenance/closed)
DELETE /facilities/:id                              (admin)

POST   /facilities/:id/images
DELETE /facilities/:id/images/:imageId

GET    /facility-categories
POST   /facility-categories                         (admin)
```

Every facilities read endpoint should enforce society scoping **server-side** from the JWT, never from a query param the client sends — same rule as Marketplace, to stop one resident from viewing another society's facilities.

## Key implementation details worth flagging now

- **Image storage**: reuse the same object store (S3/Cloudinary/Supabase Storage) set up for Marketplace — no new infra needed here.
- **Status changes should notify residents (optional, opt-in)**: e.g., "Swimming Pool closed for maintenance" — this can reuse the same notify pipeline as Visitor Management/Marketplace reports, but keep it opt-in per resident so it doesn't become noise.
- **Don't hide maintenance/closed facilities** — show them with a status badge instead of removing them from the list. Residents assuming a facility no longer exists (vs. temporarily closed) is a worse experience than showing an accurate status.
- **Keep the "Book Now" button stubbed, not absent** — this is the seam where Facility Booking (roadmap Phase 5 item) attaches later. Building the detail page with this placeholder now avoids a rebuild.

## Suggested Sprint Breakdown (~1–1.5 weeks, building on existing panels)

**Sprint 1 — Admin side + Data**
- Schema + migrations for the 3 tables above
- Image upload pipeline (reuse Marketplace's object storage integration)
- Add/Edit Facility screen (Society Admin), Facility Categories management
- `ModuleFlag` entry (`facilities`) wired into Society Admin's existing module toggle screen

**Sprint 2 — Resident-facing display**
- Facilities Page + Facility Detail (society-scoped, category filter)
- Status badges (active/maintenance/closed) reflected accurately on both list and detail
- Stubbed "Book Now" CTA on detail page (disabled, no logic)

## Definition of Done

A Society Admin can add a facility with multiple photos, description, hours, and rules in under a few minutes; toggle its status to "under maintenance" and see that reflected immediately on the User Panel; and a resident can browse all active facilities for their society only, filter by category, and view full details — with no ability to see another society's facilities and no booking functionality exposed yet.
