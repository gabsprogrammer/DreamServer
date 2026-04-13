const messagesEl = document.getElementById("messages");
const formEl = document.getElementById("chatForm");
const inputEl = document.getElementById("messageInput");
const sendButtonEl = document.getElementById("sendButton");
const statusTextEl = document.getElementById("statusText");
const latencyHintEl = document.getElementById("latencyHint");
const sessionBadgeEl = document.getElementById("sessionBadge");
const resetButtonEl = document.getElementById("resetButton");

function setText(id, value) {
  const el = document.getElementById(id);
  if (el) el.textContent = value ?? "-";
}

function appendMessage(role, body) {
  const wrapper = document.createElement("div");
  wrapper.className = `message ${role}`;

  const roleEl = document.createElement("div");
  roleEl.className = "message-role";
  roleEl.textContent = role === "user" ? "You" : "Dream";

  const bodyEl = document.createElement("div");
  bodyEl.className = "message-body";
  bodyEl.textContent = body;

  wrapper.append(roleEl, bodyEl);
  messagesEl.appendChild(wrapper);
  messagesEl.scrollTop = messagesEl.scrollHeight;
}

function updateStatus(snapshot) {
  const { model, cpu, gpu, battery, memory, storage, exports, local_url, session } = snapshot;

  setText("modelName", model?.name || "Qwen mobile");
  setText("modelMeta", `Context ${model?.context ?? "-"} • ${model?.path ?? "-"}`);

  setText("cpuTemp", cpu?.temp_c != null ? `${cpu.temp_c} C` : "No temp");
  setText("cpuMeta", `${cpu?.cores ?? "-"} cores • load ${cpu?.load_1 ?? "-"} / ${cpu?.load_5 ?? "-"}`);

  setText("gpuBusy", gpu?.available ? (gpu?.busy_percent != null ? `${gpu.busy_percent}% busy` : "online") : "Unavailable");
  setText("gpuMeta", gpu?.available ? `${gpu?.label ?? "GPU"} • ${gpu?.freq ?? "freq n/a"}${gpu?.max_freq ? ` / ${gpu.max_freq}` : ""}` : "No readable Android GPU counters");

  setText("batteryLevel", battery?.available ? `${battery?.level ?? "-"}%` : "No battery");
  setText("batteryMeta", battery?.available ? `${battery?.status ?? "unknown"}${battery?.temp_c != null ? ` • ${battery.temp_c} C` : ""}` : "Battery data unavailable");

  setText("memoryUsage", memory?.available ? `${memory.used_gb} / ${memory.total_gb} GB` : "No memory data");
  setText("storageMeta", storage?.available ? `RAM ${memory.used_percent}% • export free ${storage.export_free_gb} GB` : "Storage data unavailable");

  setText("exportDir", exports?.dir || "-");
  setText("localUrl", local_url || "-");

  sessionBadgeEl.textContent = session?.ready ? `session ready • ${session.turns} turns` : "starting session";
}

async function refreshStatus() {
  const response = await fetch("/api/status", { cache: "no-store" });
  const payload = await response.json();
  if (!payload.ok) {
    throw new Error(payload.error || "failed to load status");
  }
  updateStatus(payload.status);
}

async function sendMessage(message) {
  const response = await fetch("/api/chat", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ message }),
  });
  const payload = await response.json();
  if (!payload.ok) {
    throw new Error(payload.error || "local chat failed");
  }
  latencyHintEl.textContent = `Last reply: ${payload.latency_ms} ms`;
  return payload.reply;
}

formEl.addEventListener("submit", async (event) => {
  event.preventDefault();
  const message = inputEl.value.trim();
  if (!message) return;

  appendMessage("user", message);
  inputEl.value = "";
  inputEl.focus();
  sendButtonEl.disabled = true;
  statusTextEl.textContent = "Dream is thinking locally...";

  try {
    const reply = await sendMessage(message);
    appendMessage("assistant", reply || "(no visible response)");
    statusTextEl.textContent = "Ready.";
    await refreshStatus();
  } catch (error) {
    appendMessage("assistant", `Local error: ${error.message}`);
    statusTextEl.textContent = "The local session failed.";
  } finally {
    sendButtonEl.disabled = false;
  }
});

resetButtonEl.addEventListener("click", async () => {
  resetButtonEl.disabled = true;
  try {
    await fetch("/api/reset", { method: "POST" });
    latencyHintEl.textContent = "Session reset.";
    sessionBadgeEl.textContent = "session reset";
    messagesEl.innerHTML = "";
    appendMessage("assistant", "Fresh local session ready. Ask something new.");
    await refreshStatus();
  } finally {
    resetButtonEl.disabled = false;
  }
});

refreshStatus().catch((error) => {
  statusTextEl.textContent = error.message;
});
setInterval(() => {
  refreshStatus().catch(() => {});
}, 5000);
