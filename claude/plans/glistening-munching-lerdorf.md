# Plan: Add "Create New Project" to New Session Modal

## Goal
Enhance the new session modal to allow creating a new empty project folder in addition to selecting existing projects, using a combined combobox input.

## Implementation

### 1. Backend: Add POST /api/projects endpoint
**File:** `crates/clauset-server/src/routes/projects.rs`

Add a new `create()` handler:
```rust
#[derive(Deserialize)]
pub struct CreateProjectRequest {
    pub name: String,
}

pub async fn create(
    State(state): State<Arc<AppState>>,
    Json(req): Json<CreateProjectRequest>,
) -> Result<Json<Project>, ...> {
    // Validate name (no slashes, dots-only, etc.)
    // Create directory at projects_root/name
    // Return Project { name, path }
}
```

**File:** `crates/clauset-server/src/main.rs` (line ~151)
- Update route registration from:
  ```rust
  .route("/projects", get(routes::projects::list))
  ```
  to:
  ```rust
  .route("/projects", get(routes::projects::list).post(routes::projects::create))
  ```

### 2. Frontend API: Add projects.create method
**File:** `frontend/src/lib/api.ts`

```typescript
export interface CreateProjectRequest {
  name: string;
}

export interface CreateProjectResponse {
  name: string;
  path: string;
}

// In api.projects:
create: (req: CreateProjectRequest) =>
  fetchJSON<CreateProjectResponse>('/projects', {
    method: 'POST',
    body: JSON.stringify(req),
  }),
```

### 3. Frontend UI: Replace select with combobox
**File:** `frontend/src/components/chat/NewSessionModal.tsx`

Changes:
1. Add `inputValue` signal for the text input
2. Add `isCreatingNew` derived signal (true when inputValue doesn't match any existing project)
3. Replace `<select>` with custom combobox:
   - Text input that shows typed value
   - Dropdown list filtered by input (shows matching projects)
   - Click on dropdown item → sets input value to project path
   - When input doesn't match → show "Create new: {name}" indicator
4. Update `handleSubmit`:
   - If `isCreatingNew` → call `api.projects.create()` first
   - Use the returned path for session creation

### 4. Validation & Error Handling

**Backend validation:**
- Name must not be empty
- Name must not contain path separators (`/`, `\`)
- Name must not be `.` or `..`
- Name must not start with `.` (hidden)
- Directory must not already exist

**Frontend feedback:**
- Show "Create new project: {name}" when typing a non-existing name
- Show error if name is invalid
- Handle backend errors gracefully

## Files to Modify
1. `crates/clauset-server/src/routes/projects.rs` - Add create handler
2. `crates/clauset-server/src/routes/mod.rs` - Register POST route
3. `frontend/src/lib/api.ts` - Add create method
4. `frontend/src/components/chat/NewSessionModal.tsx` - Replace select with combobox

## Verification
- Create a new project via the modal → directory created, session starts in it
- Select existing project → works as before
- Invalid name (with `/`) → shows error
- Existing name → shows as selectable, doesn't try to create
