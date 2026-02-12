const API = '/api/tasks';

const $tasks = document.getElementById('tasks');
const $empty = document.getElementById('empty');
const $form = document.getElementById('add-form');
const $title = document.getElementById('title');
const $desc = document.getElementById('description');

let currentFilter = 'all';

// ---- Render ----

function renderTask(task) {
  const done = task.status === 'done';
  const div = document.createElement('div');
  div.className = `task-item${done ? ' done' : ''}`;
  div.dataset.id = task._id;

  div.innerHTML = `
    <div class="task-check" title="Toggle status"></div>
    <div class="task-body">
      <div class="task-title">${esc(task.title)}</div>
      ${task.description ? `<div class="task-desc">${esc(task.description)}</div>` : ''}
    </div>
    <button class="task-delete" title="Delete">&times;</button>
  `;

  div.querySelector('.task-check').addEventListener('click', () =>
    toggleTask(task._id, done ? 'pending' : 'done'),
  );
  div.querySelector('.task-delete').addEventListener('click', () => deleteTask(task._id));

  return div;
}

function renderAll(tasks) {
  $tasks.innerHTML = '';
  const visible = tasks.filter(
    (t) => currentFilter === 'all' || t.status === currentFilter,
  );
  visible.forEach((t) => $tasks.appendChild(renderTask(t)));
  $empty.classList.toggle('hidden', visible.length > 0);
}

function esc(str) {
  const d = document.createElement('div');
  d.textContent = str;
  return d.innerHTML;
}

// ---- API helpers ----

async function fetchTasks() {
  const res = await fetch(API);
  const tasks = await res.json();
  renderAll(tasks);
}

async function addTask(title, description) {
  await fetch(API, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title, description }),
  });
  await fetchTasks();
}

async function toggleTask(id, newStatus) {
  await fetch(`${API}/${id}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ $set: { status: newStatus } }),
  });
  await fetchTasks();
}

async function deleteTask(id) {
  await fetch(`${API}/${id}`, { method: 'DELETE' });
  await fetchTasks();
}

// ---- Events ----

$form.addEventListener('submit', async (e) => {
  e.preventDefault();
  const title = $title.value.trim();
  if (!title) return;
  await addTask(title, $desc.value.trim());
  $form.reset();
  $title.focus();
});

document.querySelectorAll('.filter-btn').forEach((btn) => {
  btn.addEventListener('click', () => {
    document.querySelector('.filter-btn.active').classList.remove('active');
    btn.classList.add('active');
    currentFilter = btn.dataset.filter;
    fetchTasks();
  });
});

// ---- Init ----
fetchTasks();
