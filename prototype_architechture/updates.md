# Updates Checklist

This file is a short implementation checklist for the coding agent.

Status:

- `Completed`: sections 1 through 6
- `Open`: none

It covers the updates added to the prototype architecture docs:

- hierarchical internal locations
- exhibitions
- exhibition end reminders
- rental return reminders
- move actor tracking by registered device
- iPhone-only offline movement sync

## 1. Hierarchical internal locations `[Completed]`

### Database

- Update `locations` to support self-reference with `parent_location_id`.
- Add sibling-scoped uniqueness for location names instead of global uniqueness.
- Add indexes for hierarchy traversal and sibling uniqueness.
- Keep item placement valid only for leaf locations.
- Keep internal `item_history.location_id` valid only for leaf locations.
- Prevent self-parenting and location cycles in service-layer validation.
- Do not add prototype support for moving an existing location to a different parent.

### Backend

- Update location services/entities/repositories for parent-child hierarchy.
- Add cycle validation and leaf checks.
- Keep item create/move/return flows restricted to leaf locations.
- Keep archive behavior compatible with locations that already have history or children.

### API

- Update location create payloads to accept optional `parentLocationId`.
- Keep rename separate from re-parenting.
- Return hierarchy metadata such as `parentLocationId`, full path, and assignable/leaf status.
- Allow clients to render either a tree or a flat list with parent references.

### Web and iOS

- Update location selectors to browse nested locations.
- Show full path labels like `Room > Shelf > Grid`.
- Only allow leaf nodes in item placement flows.
- Update admin location management to create root and child locations.

## 2. Exhibitions `[Completed]`

### Database

- Add `exhibitions` table.
- Add `exhibition_items` join table.
- Keep exhibition history by retaining ended exhibitions and linked item rows.
- Validate `start_date <= end_date`.
- Ensure exhibition `location_id` points to a leaf internal location.
- Reject overlapping exhibition date ranges for the same item.
- Enforce active exhibition rule: item must stay `INTERNAL` and `current_location_id` must exactly equal the exhibition location.
- Add indexes for exhibition lookup by location and dates.

### Backend

- Add exhibition module for create, edit, list, detail, and history queries.
- Validate leaf exhibition location.
- Validate date range order.
- Validate non-overlapping exhibition membership per item.
- Validate exact current location match for already active exhibitions.
- Keep ended exhibitions queryable as history.

### API

- Add exhibition endpoints for list, create, detail, and edit.
- Return exhibition phase metadata such as planned, active, ended.
- Return location path and linked item group in detail responses.
- Return enough data for clients to reschedule reminders after date edits.

### Web and iOS

- Add exhibition list/detail/create/edit flows.
- Show planned, active, and ended exhibitions.
- Show exhibition item group and location path.
- Show past exhibitions as history.

## 3. Exhibition end reminders `[Completed]`

### Backend and API

- Do not implement backend push notifications for exhibitions.
- Expose exhibition `endDate` consistently so clients can schedule local reminders.
- Ensure edit responses return the latest dates for reminder rescheduling.

### Web and iOS

- Implement client-local reminders only.
- Schedule reminder from exhibition `endDate`.
- Reschedule reminder when exhibition date range changes.
- Cancel reminder if exhibition is removed from accessible data or permission is removed.

## 4. Rental return reminders `[Completed]`

### Database

- Use open external `item_history` rows with `expected_return_date` as the source of rental reminders.
- Add an index for open external rows that have `expected_return_date`.

### Backend

- Expose reminder source data for open rentals.
- Keep reminder source data tied to the current open external history row.
- Cancel reminder source automatically when the rental row is closed by return.

### API

- Return `expectedReturnDate` for open external rentals.
- Return enough reminder context to show:
  - which item is currently external
  - which organization currently has it
  - that return is due in 3 days
- Ensure movement/history responses support reminder rescheduling when expected return date changes.

### Web and iOS

- Implement client-local rental reminders only.
- Schedule reminder 3 calendar days before `expectedReturnDate`.
- Reschedule reminder when `expectedReturnDate` changes.
- Cancel reminder when the rental is returned, disappears from accessible data, or notification permission is removed.

## 5. Move actor tracking `[Completed]`

### Database

- Use `item_history.created_by_device_id` as the movement actor record.
- Resolve that actor through `registered_devices`.
- Use `registered_devices.friendly_name` as the display name for history UI.
- Keep host-admin writes allowed to have no registered-device actor.

### Backend

- When a registered device creates a movement row, persist that device as the actor.
- When host admin performs the write through protected APIs, allow actor device to be null.
- Expose movement actor summaries for history responses.

### API

- Update history responses to include move actor metadata.
- Return fields such as actor device id, friendly name, and device type.

### Web and iOS

- Show moved-by device friendly name in history views when available.
- Handle missing actor metadata gracefully for host-admin-created rows.

## 6. iPhone-only offline movement sync `[Completed]`

### Scope

- Support offline movement on iPhone only in the prototype.
- Allow offline internal move.
- Allow offline return to internal location.
- Allow offline send-to-external only when the item already has synced planning data from an earlier online state.
- Do not support offline planning updates.
- Do not allow more than one unsynchronized offline movement per item.

### iPhone storage and behavior

- Cache the latest successful location hierarchy locally for offline movement selection.
- Keep a dedicated persistent offline-movement outbox separate from normal UI state.
- Synchronization must read only from that dedicated outbox.
- Apply local optimistic item/history state from queued movement data so the user sees the move immediately while offline.
- Mark queued or rejected offline movements clearly in the iPhone UI.

### Backend and API

- Replayed offline movement writes must include the item's expected current source placement from the iPhone's last known synced state.
- When the server receives a replayed offline movement, it must compare that expected source placement with the item's current database state before applying the new movement.
- If the current server placement does not match the queued movement's expected source placement, the server must reject that offline replay as stale instead of overwriting newer server state.
- The prototype does not require a separate offline-planning sync contract.
