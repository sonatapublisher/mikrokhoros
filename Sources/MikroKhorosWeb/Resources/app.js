const ID_PATTERN = /^[0-9a-f]{32}$/;
const PREFERENCES_KEY = "mikrokhoros.web.preferences.v1";
const PRIMARY_WEB_VIEWS = ["world", "agentManager", "inventory", "packages", "templates"];
const ROUTABLE_WEB_VIEWS = [...PRIMARY_WEB_VIEWS, "settings"];
const WEB_VIEW_META = {
  world: { label: "World", icon: "globe", description: "Explore the selected world and its active objects." },
  agentManager: { label: "Agent Manager", icon: "user-plus", description: "Create, inspect, and place agent identities." },
  inventory: { label: "Inventory", icon: "archive", description: "Browse user-owned sources available to packages and Worlds." },
  packages: { label: "Packages", icon: "package", description: "Install and inspect object packages." },
  templates: { label: "Templates", icon: "file-text", description: "Inspect trusted templates and their exact source lineage." },
  settings: { label: "Settings", icon: "gear-six", description: "Inspect mikrokhoros Web status and supported behavior." },
};
const MAX_PINS_PER_WORLD = 12;
const FOLLOW_INTERVAL_MS = 1800;
const OBJECT_CLICK_DELAY_MS = 200;
const DRAG_THRESHOLD_PX = 6;
const MIN_ZOOM = 0.55;
const MAX_ZOOM = 1.9;
const MAX_CAMERA_COORDINATE = 1_000_000;
const CONSOLE_MIN_HEIGHT = 140;
const CONSOLE_MAX_HEIGHT = 520;
const CONSOLE_DEFAULT_HEIGHT = 220;
const SIDEBAR_MIN_WIDTH = 208;
const SIDEBAR_DEFAULT_WIDTH = 240;
const SIDEBAR_MAX_WIDTH = 352;
const SIDEBAR_MIN_MAIN_WIDTH = 480;
const SIDEBAR_KEYBOARD_STEP = 12;
const SIDEBAR_LARGE_KEYBOARD_STEP = 24;
const CONSOLE_COMPLETION_DELAY_MS = 120;
const CONSOLE_MAX_ENTRIES = 60;
const CONSOLE_MAX_QUEUE_DEPTH = 16;
const SHAPES = [
  "shield",
  "square",
  "triangle",
  "pentagon",
  "hexagon",
  "seal",
  "star",
  "heart",
];
const COLORS = [
  "#246BFE",
  "#6C4DFF",
  "#A33CFF",
  "#D82D86",
  "#E54D42",
  "#E26400",
  "#9A6A00",
  "#5E7F00",
  "#009B65",
  "#00969B",
  "#007DB3",
  "#4A57D1",
];
const INTERFACE_SECTION_ORDER = ["fields", "actions", "views", "reports"];

const elements = {
  appShell: document.querySelector("#appShell"),
  worldMain: document.querySelector("#worldMain"),
  sidebarToggle: document.querySelector("#sidebarToggle"),
  sidebarResizeHandle: document.querySelector("#sidebarResizeHandle"),
  appViewTrigger: document.querySelector("#appViewTrigger"),
  appViewMenu: document.querySelector("#appViewMenu"),
  worldTrigger: document.querySelector("#worldTrigger"),
  worldTriggerLabel: document.querySelector("#worldTriggerLabel"),
  worldMenu: document.querySelector("#worldMenu"),
  humanViewButton: document.querySelector("#humanViewButton"),
  primaryAgents: document.querySelector("#primaryAgents"),
  allAgentsAnchor: document.querySelector("#allAgentsAnchor"),
  allAgentsTrigger: document.querySelector("#allAgentsTrigger"),
  allAgentsLabel: document.querySelector("#allAgentsLabel"),
  addAgentButton: document.querySelector("#addAgentButton"),
  agentsEmpty: document.querySelector("#agentsEmpty"),
  inventoryShortcut: document.querySelector("#inventoryShortcut"),
  inventoryCount: document.querySelector("#inventoryCount"),
  pinnedObjects: document.querySelector("#pinnedObjects"),
  settingsButton: document.querySelector("#settingsButton"),
  helpButton: document.querySelector("#helpButton"),
  worldContextPicker: document.querySelector("#worldContextPicker"),
  sidebarScroll: document.querySelector("#sidebarScroll"),
  domainSidebar: document.querySelector("#domainSidebar"),
  domainSearch: document.querySelector("#domainSearch"),
  domainSidebarContent: document.querySelector("#domainSidebarContent"),
  domainSidebarAction: document.querySelector("#domainSidebarAction"),
  workspaceMain: document.querySelector("#workspaceMain"),
  workspaceEyebrow: document.querySelector("#workspaceEyebrow"),
  workspaceTitle: document.querySelector("#workspaceTitle"),
  workspaceDescription: document.querySelector("#workspaceDescription"),
  webCapabilityContextActions: document.querySelector("#webCapabilityContextActions"),
  workspaceRefresh: document.querySelector("#workspaceRefresh"),
  workspaceScrollRegion: document.querySelector("#workspaceScrollRegion"),
  workspaceState: document.querySelector("#workspaceState"),
  workspaceContent: document.querySelector("#workspaceContent"),
  workspaceWelcome: document.querySelector("#workspaceWelcome"),
  workspaceWelcomeIcon: document.querySelector("#workspaceWelcomeIcon"),
  workspaceWelcomeTitle: document.querySelector("#workspaceWelcomeTitle"),
  workspaceWelcomeCopy: document.querySelector("#workspaceWelcomeCopy"),
  operationDetail: document.querySelector("#operationDetail"),
  actionBackdrop: document.querySelector("#actionBackdrop"),
  actionDialog: document.querySelector("#actionDialog"),
  actionDialogClose: document.querySelector("#actionDialogClose"),
  helpBackdrop: document.querySelector("#helpBackdrop"),
  helpDialog: document.querySelector("#helpDialog"),
  helpClose: document.querySelector("#helpClose"),
  helpSearch: document.querySelector("#helpSearch"),
  helpResults: document.querySelector("#helpResults"),
  helpEmpty: document.querySelector("#helpEmpty"),
  structuralPath: document.querySelector("#structuralPath"),
  containerBack: document.querySelector("#containerBack"),
  notificationTrigger: document.querySelector("#notificationTrigger"),
  notificationPopover: document.querySelector("#notificationPopover"),
  notificationCue: document.querySelector("#notificationCue"),
  notificationPreview: document.querySelector("#notificationPreview"),
  reportCount: document.querySelector("#reportCount"),
  reportList: document.querySelector("#reportList"),
  viewTrigger: document.querySelector("#viewTrigger"),
  viewMenu: document.querySelector("#viewMenu"),
  worldViewport: document.querySelector("#worldViewport"),
  worldLayer: document.querySelector("#worldLayer"),
  entityLayer: document.querySelector("#entityLayer"),
  cellQuickMenu: document.querySelector("#cellQuickMenu"),
  worldStatus: document.querySelector("#worldStatus"),
  zoomIndicator: document.querySelector("#zoomIndicator"),
  worldConsoleDock: document.querySelector("#worldConsoleDock"),
  worldConsolePanel: document.querySelector("#worldConsolePanel"),
  consoleResizeHandle: document.querySelector("#consoleResizeHandle"),
  consoleOutputTab: document.querySelector("#consoleOutputTab"),
  consoleAgentTab: document.querySelector("#consoleAgentTab"),
  consoleObjectTab: document.querySelector("#consoleObjectTab"),
  consoleOutputPanel: document.querySelector("#consoleOutputPanel"),
  consoleAgentPanel: document.querySelector("#consoleAgentPanel"),
  consoleObjectPanel: document.querySelector("#consoleObjectPanel"),
  consoleOutputLog: document.querySelector("#consoleOutputLog"),
  consoleOutputEmpty: document.querySelector("#consoleOutputEmpty"),
  consoleAgentContextMode: document.querySelector("#consoleAgentContextMode"),
  consoleAgentContextModeLabel: document.querySelector("#consoleAgentContextModeLabel"),
  consoleAgentKeptCoordinate: document.querySelector("#consoleAgentKeptCoordinate"),
  consoleAgentContent: document.querySelector("#consoleAgentContent"),
  consoleObjectContextMode: document.querySelector("#consoleObjectContextMode"),
  consoleObjectContextModeLabel: document.querySelector("#consoleObjectContextModeLabel"),
  consoleObjectKeptCoordinate: document.querySelector("#consoleObjectKeptCoordinate"),
  consoleObjectContent: document.querySelector("#consoleObjectContent"),
  commandSuggestions: document.querySelector("#commandSuggestions"),
  worldCommandForm: document.querySelector("#worldCommandForm"),
  worldCommandInput: document.querySelector("#worldCommandInput"),
  worldCommandSubmit: document.querySelector("#worldCommandSubmit"),
  commandHighlight: document.querySelector("#commandHighlight"),
  consoleMinimize: document.querySelector("#consoleMinimize"),
  worldCreateBackdrop: document.querySelector("#worldCreateBackdrop"),
  worldCreateDialog: document.querySelector("#worldCreateDialog"),
  worldCreateForm: document.querySelector("#worldCreateForm"),
  worldNameInput: document.querySelector("#worldNameInput"),
  worldCreateError: document.querySelector("#worldCreateError"),
  worldCreateCancel: document.querySelector("#worldCreateCancel"),
  worldCreateSubmit: document.querySelector("#worldCreateSubmit"),
  worldCreateSubmitLabel: document.querySelector("#worldCreateSubmitLabel"),
  agentAddBackdrop: document.querySelector("#agentAddBackdrop"),
  agentAddDialog: document.querySelector("#agentAddDialog"),
  agentAddForm: document.querySelector("#agentAddForm"),
  agentChoiceTrigger: document.querySelector("#agentChoiceTrigger"),
  agentChoiceMenu: document.querySelector("#agentChoiceMenu"),
  agentChoiceSymbol: document.querySelector("#agentChoiceSymbol"),
  agentChoiceValue: document.querySelector("#agentChoiceValue"),
  agentChoiceHint: document.querySelector("#agentChoiceHint"),
  agentCoordinateX: document.querySelector("#agentCoordinateX"),
  agentCoordinateY: document.querySelector("#agentCoordinateY"),
  agentAutoAdapt: document.querySelector("#agentAutoAdapt"),
  agentAddError: document.querySelector("#agentAddError"),
  agentAddCancel: document.querySelector("#agentAddCancel"),
  agentAddSubmit: document.querySelector("#agentAddSubmit"),
  agentAddSubmitLabel: document.querySelector("#agentAddSubmitLabel"),
  inspectorBackdrop: document.querySelector("#inspectorBackdrop"),
  objectInspector: document.querySelector("#objectInspector"),
  inspectorTitle: document.querySelector("#inspectorTitle"),
  inspectorType: document.querySelector("#inspectorType"),
  inspectorSymbol: document.querySelector("#inspectorSymbol"),
  inspectorIdentity: document.querySelector("#inspectorIdentity"),
  inspectorNav: document.querySelector("#inspectorNav"),
  inspectorContent: document.querySelector("#inspectorContent"),
  openContainerButton: document.querySelector("#openContainerButton"),
  pinObjectButton: document.querySelector("#pinObjectButton"),
  pinObjectLabel: document.querySelector("#pinObjectLabel"),
  inspectorClose: document.querySelector("#inspectorClose"),
  toast: document.querySelector("#toast"),
  liveRegion: document.querySelector("#liveRegion"),
};

const state = {
  snapshot: null,
  selectedObject: null,
  cameraX: 0,
  cameraY: 0,
  zoom: 1,
  labels: false,
  following: false,
  followedAgentID: null,
  followGeneration: 0,
  followTimer: null,
  followInFlight: false,
  pendingObjectActivation: null,
  pointerGesture: null,
  consumeNextEmptyCellActivation: false,
  emptyCellDismissalClearTimer: null,
  suppressNextMapClick: false,
  suppressClearTimer: null,
  keyboardCell: { x: 0, y: 0 },
  activeSurface: null,
  loadingSequence: 0,
  inspectorReturnFocus: null,
  toastTimer: null,
  zoomTimer: null,
  agentOrderByWorld: new Map(),
  expandedAgentWorlds: new Set(),
  knownWorlds: [],
  currentWorldID: null,
  worldCreateReturnFocus: null,
  worldCreateInFlight: false,
  agentAddReturnFocus: null,
  agentAddInFlight: false,
  agentAddLoading: false,
  agentAddWorldID: null,
  agentAddOptions: [],
  selectedAgentID: null,
  agentAddAutoAdapt: false,
  consoleTab: "output",
  consoleMinimized: false,
  consoleHeight: CONSOLE_DEFAULT_HEIGHT,
  consoleResizeGesture: null,
  sidebarPreferredWidth: SIDEBAR_DEFAULT_WIDTH,
  sidebarResizeGesture: null,
  consoleHover: null,
  consoleLiveCoordinate: null,
  consoleLastCoordinate: null,
  consoleContextFrozen: false,
  consoleContextWorldID: null,
  consoleContextContainerID: null,
  consoleSuggestions: [],
  consoleSuggestionIndex: -1,
  consoleCompletionSequence: 0,
  consoleCompletionTimer: null,
  consoleQueue: [],
  consoleRunning: false,
  webView: "world",
  capabilities: [],
  capabilitiesLoaded: false,
  capabilitiesError: null,
  selectedOperationID: null,
  webRequest: null,
  webCombobox: null,
  webAutocomplete: null,
  streamController: null,
  controllerTranscript: [],
  actionWorldLock: null,
  helpReturnFocus: null,
  privateRevealed: false,
  workspaceScrollPositions: new Map(),
  domainSidebarScrollPositions: new Map(),
  activeWorkspaceScrollKey: null,
};

function node(tag, className, text) {
  const value = document.createElement(tag);
  if (className) value.className = className;
  if (text !== undefined && text !== null) value.textContent = String(text);
  return value;
}

function installGlassSurfaces() {
  for (const control of document.querySelectorAll(".glass-control")) {
    if (control.querySelector(":scope > .genie-glass-wrapper")) continue;
    for (const direction of ["top-left", "bottom-right"]) {
      const wrapper = node("span", `genie-glass-wrapper is-${direction}`);
      wrapper.setAttribute("aria-hidden", "true");
      wrapper.append(node("span", "genie-glass-border"));
      control.append(wrapper);
    }
  }
}

function formatKey(value) {
  return String(value)
    .replace(/[_-]+/g, " ")
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replace(/^./, (letter) => letter.toUpperCase());
}

function safeIndex(value, count) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return 0;
  return Math.abs(Math.trunc(numeric)) % count;
}

function visualFor(value) {
  const shapeIndex = safeIndex(value?.shapeIndex, SHAPES.length);
  const colorIndex = safeIndex(value?.colorIndex, COLORS.length);
  return {
    color: COLORS[colorIndex],
    shape: SHAPES[shapeIndex],
  };
}

function applySymbol(element, identity) {
  const visual = visualFor(identity);
  element.style.setProperty("--entity-color", visual.color);
  element.style.setProperty("--entity-mask", `url("/identity-shapes/${visual.shape}.svg")`);
}

function contrastColor(hex) {
  const red = Number.parseInt(hex.slice(1, 3), 16);
  const green = Number.parseInt(hex.slice(3, 5), 16);
  const blue = Number.parseInt(hex.slice(5, 7), 16);
  const luminance = (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255;
  return luminance > 0.56 ? "#151515" : "#FFFFFF";
}

function isExactID(value) {
  return typeof value === "string" && ID_PATTERN.test(value);
}

function getCoordinates(entity) {
  const coordinate = entity?.coordinate;
  if (!coordinate) return null;
  const x = Number(coordinate.x);
  const y = Number(coordinate.y);
  if (!Number.isSafeInteger(x) || !Number.isSafeInteger(y)) return null;
  return { x, y };
}

function preferences() {
  try {
    const parsed = JSON.parse(window.localStorage.getItem(PREFERENCES_KEY) || "{}");
    const pins = parsed && typeof parsed.pins === "object" ? parsed.pins : {};
    const reports = parsed && typeof parsed.reports === "object" ? parsed.reports : {};
    const views = parsed && typeof parsed.views === "object" ? parsed.views : {};
    const inspector = parsed && typeof parsed.inspector === "object" ? parsed.inspector : {};
    const rawSidebar = parsed && typeof parsed.sidebar === "object" ? parsed.sidebar : {};
    const sidebarWidth = Number(rawSidebar.width);
    const sidebar = Number.isFinite(sidebarWidth)
      && sidebarWidth >= SIDEBAR_MIN_WIDTH
      && sidebarWidth <= SIDEBAR_MAX_WIDTH
      ? { width: Math.round(sidebarWidth) }
      : {};
    return { pins, reports, views, inspector, sidebar };
  } catch {
    return { pins: {}, reports: {}, views: {}, inspector: {}, sidebar: {} };
  }
}

function savePreferences(next) {
  try {
    window.localStorage.setItem(PREFERENCES_KEY, JSON.stringify(next));
  } catch {
    showToast("This browser could not save presentation preferences.");
  }
}

function pinnedIDs(worldID) {
  if (!isExactID(worldID)) return [];
  const stored = preferences().pins[worldID];
  if (!Array.isArray(stored)) return [];
  return Array.from(new Set(stored.filter(isExactID))).slice(0, MAX_PINS_PER_WORLD);
}

function setPinned(worldID, objectID, pinned) {
  if (!isExactID(worldID) || !isExactID(objectID)) return;
  const next = preferences();
  const values = pinnedIDs(worldID).filter((value) => value !== objectID);
  if (pinned) values.unshift(objectID);
  next.pins[worldID] = values.slice(0, MAX_PINS_PER_WORLD);
  savePreferences(next);
}

function reportSeen(worldID) {
  if (!isExactID(worldID)) return null;
  const value = preferences().reports[worldID];
  return isExactID(value) ? value : null;
}

function markLatestReportSeen() {
  const snapshot = state.snapshot;
  const report = Array.isArray(snapshot?.reports) ? snapshot.reports[0] : null;
  markReportSeen(report);
}

function markReportSeen(report) {
  const worldID = report?.worldID || state.snapshot?.selectedWorldID;
  if (!isExactID(worldID) || !isExactID(report?.id)) return;
  const next = preferences();
  next.reports[worldID] = report.id;
  savePreferences(next);
  elements.notificationCue.hidden = true;
}

function finiteCoordinate(value, fallback = 0) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return fallback;
  return Math.max(-MAX_CAMERA_COORDINATE, Math.min(MAX_CAMERA_COORDINATE, numeric));
}

function storedHumanView(worldID) {
  if (!isExactID(worldID)) return null;
  const raw = preferences().views[worldID];
  if (!raw || typeof raw !== "object") return null;
  const zoom = Number(raw.zoom);
  const keyboard = raw.keyboard && typeof raw.keyboard === "object" ? raw.keyboard : {};
  return {
    containerID: isExactID(raw.containerID) ? raw.containerID : worldID,
    cameraX: finiteCoordinate(raw.cameraX),
    cameraY: finiteCoordinate(raw.cameraY),
    zoom: Number.isFinite(zoom) ? Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, zoom)) : 1,
    keyboardCell: {
      x: Math.round(finiteCoordinate(keyboard.x)),
      y: Math.round(finiteCoordinate(keyboard.y)),
    },
  };
}

function currentHumanView() {
  const worldID = state.snapshot?.selectedWorldID;
  const containerID = state.snapshot?.container?.id;
  if (!isExactID(worldID) || !isExactID(containerID)) return null;
  return {
    containerID,
    cameraX: finiteCoordinate(state.cameraX),
    cameraY: finiteCoordinate(state.cameraY),
    zoom: Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, Number(state.zoom) || 1)),
    keyboardCell: {
      x: Math.round(finiteCoordinate(state.keyboardCell?.x)),
      y: Math.round(finiteCoordinate(state.keyboardCell?.y)),
    },
  };
}

function saveHumanView() {
  if (state.following) return;
  const worldID = state.snapshot?.selectedWorldID;
  const view = currentHumanView();
  if (!isExactID(worldID) || !view) return;
  const next = preferences();
  next.views[worldID] = view;
  savePreferences(next);
  renderHumanView();
}

function saveStoredHumanView(worldID, view) {
  if (!isExactID(worldID) || !view) return;
  const next = preferences();
  next.views[worldID] = view;
  savePreferences(next);
}

function rememberedInspectorPage(worldID, objectID) {
  if (!isExactID(worldID) || !isExactID(objectID)) return null;
  const page = preferences().inspector?.[worldID]?.[objectID];
  return typeof page === "string" && page.length <= 128 ? page : null;
}

function rememberInspectorPage(worldID, objectID, pageID) {
  if (!isExactID(worldID) || !isExactID(objectID) || typeof pageID !== "string") return;
  const next = preferences();
  if (!next.inspector[worldID] || typeof next.inspector[worldID] !== "object") {
    next.inspector[worldID] = {};
  }
  next.inspector[worldID][objectID] = pageID.slice(0, 128);
  savePreferences(next);
}

function showToast(message) {
  window.clearTimeout(state.toastTimer);
  elements.toast.textContent = message;
  elements.toast.hidden = false;
  state.toastTimer = window.setTimeout(() => {
    elements.toast.hidden = true;
  }, 3200);
}

function announce(message) {
  elements.liveRegion.textContent = "";
  window.setTimeout(() => {
    elements.liveRegion.textContent = message;
  }, 20);
}

function consoleMaximumHeight() {
  const mainHeight = elements.worldMain.getBoundingClientRect().height || window.innerHeight;
  return Math.max(
    CONSOLE_MIN_HEIGHT,
    Math.min(CONSOLE_MAX_HEIGHT, Math.floor(mainHeight * 0.52)),
  );
}

function consoleOcclusionHeight() {
  return state.consoleMinimized ? 64 : state.consoleHeight + 68;
}

function updateConsoleOcclusion() {
  elements.appShell.style.setProperty("--console-occlusion", `${consoleOcclusionHeight()}px`);
}

function setConsoleHeight(value) {
  const next = Math.round(Math.max(CONSOLE_MIN_HEIGHT, Math.min(consoleMaximumHeight(), value)));
  state.consoleHeight = next;
  elements.worldConsoleDock.style.setProperty("--console-panel-height", `${next}px`);
  elements.consoleResizeHandle.setAttribute("aria-valuemax", String(consoleMaximumHeight()));
  elements.consoleResizeHandle.setAttribute("aria-valuenow", String(next));
  updateConsoleOcclusion();
}

function isSidebarCollapsed() {
  return elements.appShell.dataset.sidebar === "collapsed";
}

function setSidebarCollapsed(collapsed) {
  elements.appShell.dataset.sidebar = collapsed ? "collapsed" : "expanded";
  elements.sidebarToggle.setAttribute("aria-pressed", collapsed ? "true" : "false");
  elements.sidebarToggle.setAttribute("aria-label", collapsed ? "Expand sidebar" : "Collapse sidebar");
  updateSidebarResizeHandle();
}

function isCompactSidebarViewport() {
  return window.matchMedia("(max-width: 760px)").matches;
}

function sidebarMaximumWidth() {
  const shellWidth = elements.appShell.getBoundingClientRect().width || window.innerWidth;
  return Math.max(
    SIDEBAR_MIN_WIDTH,
    Math.min(SIDEBAR_MAX_WIDTH, Math.floor(shellWidth - SIDEBAR_MIN_MAIN_WIDTH)),
  );
}

function normalizedSidebarPreferredWidth(value) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return SIDEBAR_DEFAULT_WIDTH;
  return Math.round(Math.max(SIDEBAR_MIN_WIDTH, Math.min(SIDEBAR_MAX_WIDTH, numeric)));
}

function effectiveSidebarWidth() {
  return Math.max(SIDEBAR_MIN_WIDTH, Math.min(sidebarMaximumWidth(), state.sidebarPreferredWidth));
}

function sidebarResizeEnabled() {
  return !isSidebarCollapsed() && !isCompactSidebarViewport();
}

function updateSidebarResizeHandle() {
  const handle = elements.sidebarResizeHandle;
  if (!handle) return;
  const enabled = sidebarResizeEnabled();
  const maximum = sidebarMaximumWidth();
  const width = Math.round(effectiveSidebarWidth());
  handle.hidden = !enabled;
  handle.tabIndex = enabled ? 0 : -1;
  handle.setAttribute("aria-hidden", enabled ? "false" : "true");
  handle.setAttribute("aria-valuemin", String(SIDEBAR_MIN_WIDTH));
  handle.setAttribute("aria-valuemax", String(maximum));
  handle.setAttribute("aria-valuenow", String(width));
  handle.setAttribute(
    "aria-valuetext",
    width === SIDEBAR_DEFAULT_WIDTH
      ? `Sidebar width ${width} pixels, default`
      : `Sidebar width ${width} pixels`,
  );
}

function applySidebarWidth() {
  elements.appShell.style.setProperty("--sidebar-preferred-width", `${state.sidebarPreferredWidth}px`);
  updateSidebarResizeHandle();
}

function restoreSidebarWidth() {
  state.sidebarPreferredWidth = normalizedSidebarPreferredWidth(preferences().sidebar?.width);
  applySidebarWidth();
}

function persistSidebarWidth() {
  const next = preferences();
  next.sidebar = { width: state.sidebarPreferredWidth };
  savePreferences(next);
}

function setSidebarPreferredWidth(value, { persist = false, constrainToViewport = true } = {}) {
  const normalized = normalizedSidebarPreferredWidth(value);
  state.sidebarPreferredWidth = constrainToViewport
    ? Math.min(sidebarMaximumWidth(), normalized)
    : normalized;
  applySidebarWidth();
  if (persist) persistSidebarWidth();
}

function finishSidebarResize({ pointerID = null, commit = false, releaseCapture = false } = {}) {
  const gesture = state.sidebarResizeGesture;
  if (!gesture || (pointerID !== null && gesture.id !== pointerID)) return;
  state.sidebarResizeGesture = null;
  elements.appShell.classList.remove("is-resizing-sidebar");
  document.body.classList.remove("is-resizing-sidebar");
  if (releaseCapture && pointerID !== null) {
    try {
      elements.sidebarResizeHandle.releasePointerCapture(pointerID);
    } catch {
      // Pointer capture may already have ended.
    }
  }
  if (commit) {
    persistSidebarWidth();
    return;
  }
  state.sidebarPreferredWidth = gesture.originPreferredWidth;
  applySidebarWidth();
}

function setConsoleMinimized(minimized) {
  state.consoleMinimized = Boolean(minimized);
  elements.worldConsoleDock.classList.toggle("is-minimized", state.consoleMinimized);
  elements.worldConsolePanel.hidden = state.consoleMinimized;
  elements.consoleMinimize.setAttribute("aria-expanded", state.consoleMinimized ? "false" : "true");
  elements.consoleMinimize.setAttribute(
    "aria-label",
    state.consoleMinimized ? "Show command information" : "Minimize command information",
  );
  updateConsoleOcclusion();
}

function selectConsoleTab(name, { focus = false } = {}) {
  const tabs = {
    output: [elements.consoleOutputTab, elements.consoleOutputPanel],
    agent: [elements.consoleAgentTab, elements.consoleAgentPanel],
    object: [elements.consoleObjectTab, elements.consoleObjectPanel],
  };
  if (!tabs[name]) return;
  state.consoleTab = name;
  for (const [key, [tab, panel]] of Object.entries(tabs)) {
    const selected = key === name;
    tab.classList.toggle("is-selected", selected);
    tab.setAttribute("aria-selected", selected ? "true" : "false");
    tab.tabIndex = selected ? 0 : -1;
    panel.hidden = !selected;
  }
  renderConsoleContextMode();
  if (focus) tabs[name][0].focus({ preventScroll: true });
}

function syntaxSpan(className, text) {
  const span = node("span", className);
  span.textContent = text;
  return span;
}

function renderCommandHighlight() {
  const source = elements.worldCommandInput.value;
  const fragment = document.createDocumentFragment();
  let index = 0;
  let tokenIndex = 0;
  let commandBudget = 3;
  while (index < source.length) {
    const character = source[index];
    if (/\s/u.test(character)) {
      let end = index + 1;
      while (end < source.length && /\s/u.test(source[end])) end += 1;
      fragment.append(document.createTextNode(source.slice(index, end)));
      index = end;
      continue;
    }
    if (character === "\"" || character === "'") {
      const quote = character;
      let end = index + 1;
      let escaping = false;
      let closed = false;
      while (end < source.length) {
        const current = source[end];
        if (escaping) escaping = false;
        else if (current === "\\" && quote === "\"") escaping = true;
        else if (current === quote) {
          end += 1;
          closed = true;
          break;
        }
        end += 1;
      }
      fragment.append(syntaxSpan(closed ? "syntax-string" : "syntax-error", source.slice(index, end)));
      tokenIndex += 1;
      index = end;
      continue;
    }
    let end = index + 1;
    while (end < source.length && !/\s/u.test(source[end]) && source[end] !== "\"" && source[end] !== "'") {
      end += 1;
    }
    const token = source.slice(index, end);
    if (tokenIndex === 0 && token.toLowerCase() === "khoros") commandBudget = 4;
    let className = "syntax-text";
    if (token.startsWith("--")) className = "syntax-option";
    else if (/^-?\d+(?:,-?\d+)?$/u.test(token)) className = "syntax-number";
    else if (tokenIndex < commandBudget) className = "syntax-command";
    fragment.append(syntaxSpan(className, token));
    tokenIndex += 1;
    index = end;
  }
  elements.commandHighlight.replaceChildren(fragment);
  elements.commandHighlight.scrollLeft = elements.worldCommandInput.scrollLeft;
}

function closeCommandSuggestions() {
  state.consoleSuggestions = [];
  state.consoleSuggestionIndex = -1;
  elements.commandSuggestions.replaceChildren();
  elements.commandSuggestions.hidden = true;
  elements.worldCommandInput.setAttribute("aria-expanded", "false");
  elements.worldCommandInput.setAttribute("aria-activedescendant", "");
}

function setCommandSuggestionIndex(index) {
  const count = state.consoleSuggestions.length;
  if (!count) return;
  state.consoleSuggestionIndex = (index + count) % count;
  for (const [itemIndex, row] of Array.from(elements.commandSuggestions.children).entries()) {
    const selected = itemIndex === state.consoleSuggestionIndex;
    row.classList.toggle("is-selected", selected);
    row.setAttribute("aria-selected", selected ? "true" : "false");
    if (selected) row.scrollIntoView({ block: "nearest" });
  }
  elements.worldCommandInput.setAttribute(
    "aria-activedescendant",
    `commandSuggestion${state.consoleSuggestionIndex}`,
  );
}

function acceptCommandSuggestion(index = state.consoleSuggestionIndex) {
  const suggestion = state.consoleSuggestions[index];
  if (!suggestion) return false;
  elements.worldCommandInput.value = suggestion.value;
  renderCommandHighlight();
  closeCommandSuggestions();
  elements.worldCommandInput.focus({ preventScroll: true });
  return true;
}

function validCommandSuggestions(result) {
  if (!result || typeof result !== "object" || Array.isArray(result)) return null;
  if (Object.keys(result).sort().join(",") !== "suggestions") return null;
  if (!Array.isArray(result.suggestions) || result.suggestions.length > 8) return null;
  const suggestions = [];
  for (const value of result.suggestions) {
    if (
      !value
      || typeof value !== "object"
      || Array.isArray(value)
      || Object.keys(value).sort().join(",") !== "summary,value"
      || typeof value.value !== "string"
      || typeof value.summary !== "string"
      || Array.from(value.value).length > 4096
      || value.value.includes("\n")
      || value.value.includes("\r")
      || Array.from(value.summary).length > 512
    ) return null;
    suggestions.push(value);
  }
  return suggestions;
}

function renderCommandSuggestions(suggestions) {
  elements.commandSuggestions.replaceChildren();
  state.consoleSuggestions = suggestions;
  if (!suggestions.length) {
    closeCommandSuggestions();
    return;
  }
  suggestions.forEach((suggestion, index) => {
    const row = node("button", "command-suggestion");
    row.id = `commandSuggestion${index}`;
    row.type = "button";
    row.setAttribute("role", "option");
    row.setAttribute("aria-selected", "false");
    row.append(node("code", "", suggestion.value));
    row.append(node("span", "", suggestion.summary));
    row.addEventListener("pointerdown", (event) => {
      event.preventDefault();
      acceptCommandSuggestion(index);
    });
    elements.commandSuggestions.append(row);
  });
  elements.commandSuggestions.hidden = false;
  elements.worldCommandInput.setAttribute("aria-expanded", "true");
  setCommandSuggestionIndex(0);
}

function scheduleCommandCompletions() {
  window.clearTimeout(state.consoleCompletionTimer);
  const source = elements.worldCommandInput.value;
  const sequence = ++state.consoleCompletionSequence;
  if (!source.trim() || !isExactID(state.snapshot?.selectedWorldID)) {
    closeCommandSuggestions();
    return;
  }
  state.consoleCompletionTimer = window.setTimeout(async () => {
    try {
      const result = await requestWorldCommand("completions", source);
      if (sequence !== state.consoleCompletionSequence || source !== elements.worldCommandInput.value) return;
      const suggestions = validCommandSuggestions(result);
      if (!suggestions) throw new Error("request");
      renderCommandSuggestions(suggestions.filter((value) => value.value !== source));
    } catch {
      if (sequence === state.consoleCompletionSequence) closeCommandSuggestions();
    }
  }, CONSOLE_COMPLETION_DELAY_MS);
}

function consoleEntry({ status = "Running…" } = {}) {
  const log = elements.consoleOutputLog;
  const shouldStick = log.scrollHeight - log.scrollTop - log.clientHeight < 28;
  elements.consoleOutputEmpty.hidden = true;
  const entry = node("article", "console-output-entry");
  const heading = node("div", "console-output-command");
  heading.append(node("span", "", "›"));
  const command = node("code", "", "Running command…");
  const stateLabel = node("span", "console-output-status", status);
  heading.append(command);
  heading.append(stateLabel);
  entry.append(heading);
  log.append(entry);
  while (log.querySelectorAll(".console-output-entry").length > CONSOLE_MAX_ENTRIES) {
    log.querySelector(".console-output-entry")?.remove();
  }
  if (shouldStick) log.scrollTop = log.scrollHeight;
  return { entry, command, stateLabel, shouldStick };
}

function finishConsoleEntry(parts, result) {
  const log = elements.consoleOutputLog;
  const shouldStick = parts.shouldStick
    || log.scrollHeight - log.scrollTop - log.clientHeight < 28;
  parts.command.textContent = result.displayCommand;
  parts.stateLabel.textContent = result.exitStatus === 0 ? "Done" : `Exit ${result.exitStatus}`;
  parts.stateLabel.classList.toggle("is-success", result.exitStatus === 0);
  parts.stateLabel.classList.toggle("is-error", result.exitStatus !== 0);
  if (result.standardOutput) {
    const output = node("pre", "console-output-stream");
    output.setAttribute("aria-label", "Standard output");
    output.textContent = result.standardOutput;
    parts.entry.append(output);
  }
  if (result.standardError) {
    const error = node("pre", "console-output-stream is-error");
    error.setAttribute("aria-label", "Standard error");
    error.textContent = result.standardError;
    parts.entry.append(error);
  }
  if (!result.standardOutput && !result.standardError && result.exitStatus === 0) {
    parts.entry.append(node("pre", "console-output-stream", "Command completed."));
  }
  if (result.outputTruncated) {
    parts.entry.append(node("p", "console-truncated-note", "Output reached the World console limit."));
  }
  if (shouldStick) log.scrollTop = log.scrollHeight;
}

function validCommandExecution(result) {
  if (!result || typeof result !== "object" || Array.isArray(result)) return false;
  if (
    Object.keys(result).sort().join(",")
      !== "accepted,displayCommand,exitStatus,outputTruncated,refreshWorld,standardError,standardOutput"
  ) return false;
  return typeof result.accepted === "boolean"
    && typeof result.displayCommand === "string"
    && typeof result.standardOutput === "string"
    && typeof result.standardError === "string"
    && Number.isInteger(result.exitStatus)
    && typeof result.outputTruncated === "boolean"
    && typeof result.refreshWorld === "boolean"
    && Array.from(result.displayCommand).length <= 4096
    && Array.from(result.standardOutput).length <= 131072
    && Array.from(result.standardError).length <= 131072;
}

async function processConsoleQueue() {
  if (state.consoleRunning || !state.consoleQueue.length) return;
  const source = state.consoleQueue.shift();
  state.consoleRunning = true;
  const parts = consoleEntry();
  try {
    const result = await requestWorldCommand("execute", source);
    if (!validCommandExecution(result)) throw new Error("request");
    finishConsoleEntry(parts, result);
    if (result.refreshWorld && result.exitStatus === 0) {
      await loadWorld({
        route: currentRoute(),
        mode: state.following ? "follow-refresh" : "preserve-camera",
        quiet: true,
      });
    }
  } catch (error) {
    const message = error?.code === "busy"
      ? "Another World command is already running. This command was not retried."
      : error?.code === "session"
        ? "The local browser session has ended. Restart khoros web."
        : error?.code === "world"
          ? "Choose an available World before running a command."
          : "The World command service could not complete this request.";
    finishConsoleEntry(parts, {
      displayCommand: "command request",
      standardOutput: "",
      standardError: message,
      exitStatus: 1,
      outputTruncated: false,
    });
  } finally {
    state.consoleRunning = false;
    if (state.consoleQueue.length) window.queueMicrotask(processConsoleQueue);
  }
}

function submitWorldCommand(event) {
  event.preventDefault();
  const source = elements.worldCommandInput.value.trim();
  if (!source) return;
  if (!isExactID(state.snapshot?.selectedWorldID)) {
    showToast("Choose an available World before running a command.");
    return;
  }
  if (state.consoleQueue.length >= CONSOLE_MAX_QUEUE_DEPTH) {
    showToast("The World command queue is full.");
    return;
  }
  state.consoleQueue.push(source);
  elements.worldCommandInput.value = "";
  renderCommandHighlight();
  closeCommandSuggestions();
  selectConsoleTab("output");
  if (state.consoleMinimized) setConsoleMinimized(false);
  processConsoleQueue();
}

function consoleDataRow(key, value, { mono = false } = {}) {
  const row = node("div", "console-data-row");
  row.append(node("span", "console-data-key", key));
  row.append(node("span", `console-data-value${mono ? " is-mono" : ""}`, value));
  return row;
}

function consoleContextHeading(entity, subtitle) {
  const heading = node("div", "console-context-heading");
  const symbol = node("span", "console-context-symbol");
  applySymbol(symbol, entity.visual);
  const copy = node("span", "row-copy");
  copy.append(node("strong", "", entity.name));
  copy.append(node("code", "", subtitle));
  heading.append(symbol);
  heading.append(copy);
  return heading;
}

function renderConsoleAgentContext() {
  const content = elements.consoleAgentContent;
  content.replaceChildren();
  const coordinate = state.consoleHover?.coordinate;
  if (!coordinate) {
    content.append(node("p", "console-empty-state", "Point to a World cell to inspect its agents."));
    return;
  }
  const agents = occupantsAt(coordinate).agents;
  if (!agents.length) {
    content.append(node("p", "console-empty-state", `No agent at (${coordinate.x},${coordinate.y}).`));
    return;
  }
  for (const agent of agents) {
    const group = node("article", "console-context-group");
    group.append(consoleContextHeading(agent, `agent · (${coordinate.x},${coordinate.y})`));
    group.append(consoleDataRow("Identity", agent.id, { mono: true }));
    group.append(consoleDataRow("Path", agent.path || "world", { mono: true }));
    group.append(consoleDataRow("State", agent.isFocused ? "Focused" : "Active"));
    const holding = agent.primaryHeldObject?.visual;
    group.append(
      consoleDataRow(
        "Primary holding",
        holding ? `${visualFor(holding).shape} · color ${holding.colorIndex + 1}` : "None",
      ),
    );
    content.append(group);
  }
}

function renderConsoleObjectContext() {
  const content = elements.consoleObjectContent;
  content.replaceChildren();
  const coordinate = state.consoleHover?.coordinate;
  if (!coordinate) {
    content.append(node("p", "console-empty-state", "Point to a World cell to inspect its object."));
    return;
  }
  const objects = occupantsAt(coordinate).objects;
  if (!objects.length) {
    content.append(node("p", "console-empty-state", `No object at (${coordinate.x},${coordinate.y}).`));
    return;
  }
  for (const object of objects) {
    const group = node("article", "console-context-group");
    group.append(consoleContextHeading(object, `${object.type} · (${coordinate.x},${coordinate.y})`));
    group.append(consoleDataRow("Identity", object.id, { mono: true }));
    group.append(consoleDataRow("Path", object.path || "world", { mono: true }));
    group.append(consoleDataRow("Container", object.hasContainer ? "Openable" : "No"));
    group.append(consoleDataRow("Summary", object.summary || "No summary"));
    content.append(group);
  }
}

function renderConsoleContext() {
  renderConsoleAgentContext();
  renderConsoleObjectContext();
  renderConsoleContextMode();
}

function setConsoleHover(coordinate) {
  state.consoleLiveCoordinate = coordinate ? { ...coordinate } : null;
  if (state.consoleLiveCoordinate) state.consoleLastCoordinate = { ...state.consoleLiveCoordinate };
  if (state.consoleContextFrozen) return;
  state.consoleHover = state.consoleLiveCoordinate
    ? { coordinate: { ...state.consoleLiveCoordinate } }
    : null;
  renderConsoleContext();
}

function renderConsoleContextMode() {
  const coordinate = state.consoleHover?.coordinate;
  const modeControls = [
    [elements.consoleAgentContextMode, elements.consoleAgentContextModeLabel, elements.consoleAgentKeptCoordinate],
    [elements.consoleObjectContextMode, elements.consoleObjectContextModeLabel, elements.consoleObjectKeptCoordinate],
  ];
  for (const [control, label, keptCoordinate] of modeControls) {
    control.classList.toggle("is-kept", state.consoleContextFrozen);
    control.setAttribute("aria-pressed", state.consoleContextFrozen ? "true" : "false");
    label.textContent = state.consoleContextFrozen ? "to follow hover" : "to keep detail";
    keptCoordinate.hidden = !state.consoleContextFrozen || !coordinate;
    keptCoordinate.textContent = coordinate ? `(${coordinate.x},${coordinate.y})` : "";
    control.setAttribute(
      "aria-label",
      state.consoleContextFrozen && coordinate
        ? `Press C to follow hover. Detail kept at (${coordinate.x},${coordinate.y}).`
        : "Press C to keep the current detail.",
    );
  }
}

function clearConsoleContext() {
  state.consoleLiveCoordinate = null;
  state.consoleLastCoordinate = null;
  state.consoleHover = null;
  state.consoleContextFrozen = false;
  renderConsoleContext();
}

function toggleConsoleContextFreeze() {
  if (state.consoleTab !== "agent" && state.consoleTab !== "object") return;
  const label = state.consoleTab === "agent" ? "Agent" : "Object";
  if (state.consoleContextFrozen) {
    state.consoleContextFrozen = false;
    state.consoleHover = state.consoleLiveCoordinate
      ? { coordinate: { ...state.consoleLiveCoordinate } }
      : null;
    renderConsoleContext();
    announce(`${label} detail now follows World cells.`);
    return;
  }
  const coordinate = state.consoleHover?.coordinate || state.consoleLastCoordinate;
  if (!coordinate) {
    showToast("Point to a World cell before keeping its detail.");
    announce("Point to a World cell before keeping its detail.");
    return;
  }
  state.consoleHover = { coordinate: { ...coordinate } };
  state.consoleContextFrozen = true;
  renderConsoleContext();
  announce(`${label} detail kept at (${coordinate.x},${coordinate.y}).`);
}

function reconcileConsoleContext(previousSnapshot, nextSnapshot) {
  const previousWorld = previousSnapshot?.selectedWorldID;
  const previousContainer = previousSnapshot?.container?.id;
  const nextWorld = nextSnapshot?.selectedWorldID;
  const nextContainer = nextSnapshot?.container?.id;
  if (previousWorld !== nextWorld || previousContainer !== nextContainer) {
    state.consoleLiveCoordinate = null;
    state.consoleLastCoordinate = null;
    state.consoleHover = null;
    state.consoleContextFrozen = false;
  }
  state.consoleContextWorldID = nextWorld || null;
  state.consoleContextContainerID = nextContainer || null;
  renderConsoleContext();
}

function setWorldCommandAvailability(available) {
  elements.worldCommandInput.disabled = !available;
  elements.worldCommandSubmit.disabled = !available;
  elements.worldCommandInput.placeholder = available ? "world show" : "Choose an available World";
  if (!available) closeCommandSuggestions();
}

function setStatus(title, description, symbol = "circle-notch") {
  const heading = elements.worldStatus.querySelector("h1");
  const paragraph = elements.worldStatus.querySelector("p");
  const image = elements.worldStatus.querySelector("img");
  heading.textContent = title;
  paragraph.textContent = description;
  image.src = `/icons/phosphor/${symbol}.svg`;
  elements.worldStatus.hidden = false;
}

function clearStatus() {
  elements.worldStatus.hidden = true;
}

async function establishSession() {
  const rawFragment = window.location.hash.startsWith("#")
    ? window.location.hash.slice(1)
    : "";
  const token = rawFragment.startsWith("token=")
    ? rawFragment.slice("token=".length)
    : rawFragment;
  if (!token) return;

  window.history.replaceState(
    {},
    "",
    `${window.location.pathname}${window.location.search}`,
  );

  const response = await window.fetch("/api/v1/session", {
    method: "POST",
    credentials: "same-origin",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ token }),
  });
  if (!response.ok) {
    throw new Error("session");
  }
}

async function requestJSON(path) {
  const response = await window.fetch(path, {
    method: "GET",
    credentials: "same-origin",
    headers: { Accept: "application/json" },
  });
  if (response.status === 401 || response.status === 403) {
    const error = new Error("session");
    error.code = "session";
    throw error;
  }
  if (!response.ok) {
    const error = new Error("request");
    error.code = "request";
    throw error;
  }
  return response.json();
}

async function requestWorldCommand(endpoint, source) {
  const worldID = state.snapshot?.selectedWorldID;
  if (!isExactID(worldID)) {
    const error = new Error("world");
    error.code = "world";
    throw error;
  }
  const response = await window.fetch(`/api/v1/world-command/${endpoint}`, {
    method: "POST",
    credentials: "same-origin",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ worldID, source }),
  });
  if (response.status === 401 || response.status === 403) {
    const error = new Error("session");
    error.code = "session";
    throw error;
  }
  if (response.status === 409) {
    const error = new Error("busy");
    error.code = "busy";
    throw error;
  }
  if (!response.ok) {
    const error = new Error("request");
    error.code = "request";
    throw error;
  }
  return response.json();
}

async function requestWorldCreation(name) {
  const response = await window.fetch("/api/v1/worlds", {
    method: "POST",
    credentials: "same-origin",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ name }),
  });
  if (response.status === 401 || response.status === 403) {
    const error = new Error("session");
    error.code = "session";
    throw error;
  }
  if (response.status === 400 || response.status === 422) {
    const error = new Error("validation");
    error.code = "validation";
    throw error;
  }
  if (response.status !== 201) {
    const error = new Error("request");
    error.code = "request";
    throw error;
  }
  const result = await response.json().catch(() => null);
  const keys = result && typeof result === "object" && !Array.isArray(result)
    ? Object.keys(result).sort()
    : [];
  if (
    keys.length !== 2
    || keys[0] !== "id"
    || keys[1] !== "name"
    || !isExactID(result.id)
    || typeof result.name !== "string"
    || Array.from(result.name).length > 128
    || result.name.includes("\n")
    || result.name.includes("\r")
  ) {
    const error = new Error("request");
    error.code = "request";
    throw error;
  }
  return result;
}

function isVisualIdentity(value) {
  return (
    value
    && typeof value === "object"
    && !Array.isArray(value)
    && Object.keys(value).sort().join(",") === "colorIndex,shapeIndex"
    && Number.isInteger(value.shapeIndex)
    && value.shapeIndex >= 0
    && value.shapeIndex < SHAPES.length
    && Number.isInteger(value.colorIndex)
    && value.colorIndex >= 0
    && value.colorIndex < COLORS.length
  );
}

function isAgentDisplayName(value) {
  return (
    typeof value === "string"
    && Array.from(value).length > 0
    && Array.from(value).length <= 128
    && !value.includes("\n")
    && !value.includes("\r")
  );
}

async function requestWorldAgentOptions(worldID) {
  const result = await requestJSON(`/api/v1/world-agents?world=${encodeURIComponent(worldID)}`);
  const keys = result && typeof result === "object" && !Array.isArray(result)
    ? Object.keys(result).sort()
    : [];
  const validStates = new Set(["available", "present", "assignedElsewhere"]);
  if (
    keys.length !== 2
    || keys[0] !== "agents"
    || keys[1] !== "worldID"
    || result.worldID !== worldID
    || !Array.isArray(result.agents)
  ) {
    throw new Error("request");
  }
  const seen = new Set();
  for (const agent of result.agents) {
    const agentKeys = agent && typeof agent === "object" && !Array.isArray(agent)
      ? Object.keys(agent).sort()
      : [];
    if (
      agentKeys.join(",") !== "id,name,state,visual"
      || !isExactID(agent.id)
      || seen.has(agent.id)
      || !isAgentDisplayName(agent.name)
      || !validStates.has(agent.state)
      || !isVisualIdentity(agent.visual)
    ) {
      throw new Error("request");
    }
    seen.add(agent.id);
  }
  return result;
}

async function requestWorldAgentAddition(payload) {
  const response = await window.fetch("/api/v1/world-agents", {
    method: "POST",
    credentials: "same-origin",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  if (response.status === 401 || response.status === 403) {
    const error = new Error("session");
    error.code = "session";
    throw error;
  }
  if (response.status === 400 || response.status === 422) {
    const error = new Error("validation");
    error.code = "validation";
    throw error;
  }
  if (response.status === 409) {
    const error = new Error("conflict");
    error.code = "conflict";
    throw error;
  }
  if (response.status !== 201) {
    const error = new Error("request");
    error.code = "request";
    throw error;
  }
  const result = await response.json().catch(() => null);
  const keys = result && typeof result === "object" && !Array.isArray(result)
    ? Object.keys(result).sort()
    : [];
  const validCoordinate = (value) => (
    value
    && typeof value === "object"
    && !Array.isArray(value)
    && Object.keys(value).sort().join(",") === "x,y"
    && Number.isSafeInteger(value.x)
    && Number.isSafeInteger(value.y)
  );
  if (
    keys.join(",") !== "actual,adapted,agentID,name,requested,worldID"
    || result.worldID !== payload.worldID
    || result.agentID !== payload.agentID
    || !isAgentDisplayName(result.name)
    || typeof result.adapted !== "boolean"
    || !validCoordinate(result.requested)
    || !validCoordinate(result.actual)
  ) {
    const error = new Error("request");
    error.code = "request";
    throw error;
  }
  return result;
}

function closeActiveSurface({ restoreFocus = true } = {}) {
  const active = state.activeSurface;
  if (!active) return;
  active.panel.hidden = true;
  active.trigger.setAttribute("aria-expanded", "false");
  state.activeSurface = null;
  if (restoreFocus) active.trigger.focus({ preventScroll: true });
}

function openSurface(trigger, panel, { focusFirst = true } = {}) {
  if (state.activeSurface?.panel === panel) {
    closeActiveSurface();
    return;
  }
  closeActiveSurface({ restoreFocus: false });
  panel.hidden = false;
  trigger.setAttribute("aria-expanded", "true");
  state.activeSurface = { trigger, panel };
  if (focusFirst && panel.getAttribute("role") === "menu") {
    const first = menuItems(panel)[0];
    first?.focus({ preventScroll: true });
  }
}

function menuItems(menu) {
  return Array.from(menu.querySelectorAll("[role^='menuitem']")).filter(
    (item) => item.getAttribute("aria-disabled") !== "true",
  );
}

function menuKeyboard(event) {
  const menu = event.currentTarget;
  const items = menuItems(menu);
  if (!items.length) return;
  const current = items.indexOf(document.activeElement);
  let target = null;
  if (event.key === "ArrowDown") target = items[(current + 1 + items.length) % items.length];
  if (event.key === "ArrowUp") target = items[(current - 1 + items.length) % items.length];
  if (event.key === "Home") target = items[0];
  if (event.key === "End") target = items[items.length - 1];
  if (target) {
    event.preventDefault();
    target.focus();
  }
  if ((event.key === "Enter" || event.key === " ") && current >= 0) {
    event.preventDefault();
    items[current].click();
  }
  if (event.key === "Escape") {
    event.preventDefault();
    closeActiveSurface();
  }
}

function wireSurface(trigger, panel, options) {
  trigger.addEventListener("click", () => openSurface(trigger, panel, options));
  panel.addEventListener("keydown", menuKeyboard);
}

function worldAPIPath(route = currentRoute()) {
  const parameters = new URLSearchParams();
  if (route.world) parameters.set("world", route.world);
  if (route.container) parameters.set("container", route.container);
  if (route.focus) parameters.set("focus", route.focus);
  const query = parameters.toString();
  return query ? `/api/v1/world?${query}` : "/api/v1/world";
}

async function loadWorld({
  route = currentRoute(),
  mode = "preserve-camera",
  camera = null,
  quiet = false,
  suppressUnavailable = false,
  synchronizeRoute = true,
} = {}) {
  const sequence = ++state.loadingSequence;
  if (!quiet) {
    setStatus("Opening World…", "Reading the selected mikrokhoros world.");
    closeActiveSurface({ restoreFocus: false });
  }

  try {
    const snapshot = await requestJSON(worldAPIPath(route));
    if (sequence !== state.loadingSequence) return false;
    const previousSnapshot = state.snapshot;
    state.snapshot = snapshot;
    reconcileConsoleContext(previousSnapshot, snapshot);
    if (mode !== "follow-refresh") state.selectedObject = null;
    renderSnapshot(mode, camera);

    if (
      synchronizeRoute
      && isExactID(snapshot.selectedWorldID)
      && currentRoute().world !== snapshot.selectedWorldID
    ) {
      const container = snapshot.container?.id;
      updateRoute(
        {
          world: snapshot.selectedWorldID,
          container: !state.following && isExactID(container) && container !== snapshot.selectedWorldID
            ? container
            : null,
          focus: state.following ? state.followedAgentID : null,
        },
        "replace",
      );
    }
    return true;
  } catch (error) {
    if (sequence !== state.loadingSequence) return false;
    if (suppressUnavailable) return false;
    state.snapshot = null;
    renderUnavailable(
      error?.code === "session"
        ? "Restart khoros web and open its new launch link."
        : "The local World projection could not be read.",
    );
    return false;
  }
}

function renderSnapshot(mode, camera = null) {
  const snapshot = state.snapshot;
  renderWorldPicker(snapshot);
  renderAgents(snapshot);
  renderReports(snapshot);
  renderInventory(snapshot);
  renderPins();

  const available = snapshot?.state === "available" && isExactID(snapshot.selectedWorldID);
  if (!available) {
    setWorldCommandAvailability(false);
    clearConsoleContext();
    const empty = snapshot?.state === "empty";
    setStatus(
      empty ? "Create your first world" : "This world could not be opened",
      empty
        ? "Open the World menu and choose Create new world."
        : "Choose another world or create a new one from the World menu.",
      empty ? "globe" : "shield",
    );
    elements.structuralPath.textContent = "world";
    elements.worldLayer.replaceChildren();
    elements.entityLayer.replaceChildren();
    return;
  }

  setWorldCommandAvailability(true);
  clearStatus();
  updateStructuralPath(snapshot);
  elements.containerBack.hidden = !snapshot.container?.parentContainerID;
  elements.worldTrigger.disabled = false;

  if (mode === "follow" || mode === "follow-refresh") {
    recenterOnFollow(false);
  } else if (mode === "restore-human" || mode === "reset-human") {
    state.following = false;
    state.followedAgentID = null;
    updateStructuralPath(snapshot);
    const validCamera = camera && camera.containerID === snapshot.container?.id;
    state.cameraX = validCamera ? finiteCoordinate(camera.cameraX) : 0;
    state.cameraY = validCamera ? finiteCoordinate(camera.cameraY) : 0;
    state.zoom = validCamera
      ? Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, Number(camera.zoom) || 1))
      : 1;
    state.keyboardCell = validCamera
      ? {
          x: Math.round(finiteCoordinate(camera.keyboardCell?.x)),
          y: Math.round(finiteCoordinate(camera.keyboardCell?.y)),
        }
      : { x: 0, y: 0 };
    renderWorld();
    saveHumanView();
  } else if (Number.isFinite(state.cameraX) && Number.isFinite(state.cameraY)) {
    renderWorld();
  } else {
    state.cameraX = 0;
    state.cameraY = 0;
    renderWorld();
  }
  renderAgents(snapshot);
  renderHumanView();
}

function activeFollowedAgent(snapshot = state.snapshot) {
  if (
    !state.following
    || !isExactID(state.followedAgentID)
    || snapshot?.state !== "available"
    || snapshot?.focusedAgentID !== state.followedAgentID
  ) return null;
  return [
    ...(Array.isArray(snapshot?.primaryAgents) ? snapshot.primaryAgents : []),
    ...(Array.isArray(snapshot?.otherAgents) ? snapshot.otherAgents : []),
  ].find((agent) => agent.id === state.followedAgentID) || null;
}

function structuralPathForSnapshot(snapshot = state.snapshot) {
  const followed = activeFollowedAgent(snapshot);
  if (typeof followed?.path === "string" && followed.path.trim()) return followed.path;
  return snapshot?.container?.path || "world";
}

function updateStructuralPath(snapshot = state.snapshot) {
  elements.structuralPath.textContent = structuralPathForSnapshot(snapshot);
}

function renderUnavailable(description) {
  setWorldCommandAvailability(false);
  clearConsoleContext();
  renderWorldPicker(null);
  renderAgents(null);
  elements.pinnedObjects.replaceChildren();
  elements.reportList.replaceChildren();
  elements.worldLayer.replaceChildren();
  elements.entityLayer.replaceChildren();
  elements.cellQuickMenu.replaceChildren();
  elements.structuralPath.textContent = "world";
  elements.notificationPreview.textContent = "No reports";
  elements.notificationCue.hidden = true;
  setStatus("This world could not be opened", description, "shield");
}

function renderWorldPicker(snapshot) {
  if (Array.isArray(snapshot?.worlds)) {
    state.knownWorlds = snapshot.worlds.filter(
      (world) => isExactID(world?.id) && typeof world?.name === "string",
    );
    state.currentWorldID = isExactID(snapshot.currentWorldID)
      ? snapshot.currentWorldID
      : state.knownWorlds.find((world) => world.isCurrent)?.id || null;
  }
  const worlds = state.knownWorlds;
  const selected = worlds.find((world) => world.id === snapshot?.selectedWorldID);
  const triggerLabel = selected?.name || (worlds.length ? "Choose world" : "Create a world");
  elements.worldTriggerLabel.textContent = triggerLabel;
  elements.worldTrigger.setAttribute(
    "aria-label",
    selected ? `Choose world. Current world: ${selected.name}` : triggerLabel,
  );
  elements.worldTrigger.title = selected ? `${selected.name} · ${selected.id}` : triggerLabel;
  elements.worldTrigger.disabled = false;
  elements.worldMenu.replaceChildren();

  for (const world of worlds) {
    const row = node("button", "menu-row");
    row.type = "button";
    row.setAttribute("role", "menuitemradio");
    row.setAttribute("aria-checked", world.id === snapshot?.selectedWorldID ? "true" : "false");
    if (world.id === snapshot?.selectedWorldID) row.classList.add("is-selected");
    row.append(icon("globe"));

    const copy = node("span");
    copy.className = "row-copy";
    copy.append(node("span", "row-title", world.name));
    copy.append(node("code", "row-subtitle identity-code", world.id));
    row.append(copy);

    if (world.id === snapshot?.selectedWorldID) {
      row.append(icon("check", "menu-check", "Viewed world"));
    } else if (world.isCurrent || world.id === state.currentWorldID) {
      row.append(node("span", "menu-meta", "Current"));
    } else {
      row.append(node("span", "menu-meta", ""));
    }

    row.addEventListener("click", () => {
      closeActiveSurface({ restoreFocus: false });
      restoreHumanViewForWorld(world.id, { returnFocus: elements.worldTrigger });
    });
    elements.worldMenu.append(row);
  }

  const createRow = node("button", "menu-row create-world-row");
  createRow.type = "button";
  createRow.setAttribute("role", "menuitem");
  createRow.append(icon("plus"));
  createRow.append(node("span", "row-title", "Create new world"));
  createRow.append(node("span", "menu-meta", ""));
  createRow.addEventListener("click", openWorldCreateDialog);
  elements.worldMenu.append(createRow);
}

function openWorldCreateDialog() {
  closeActiveSurface({ restoreFocus: false });
  state.worldCreateReturnFocus = elements.worldTrigger;
  elements.worldCreateError.hidden = true;
  elements.worldCreateError.textContent = "";
  if (!elements.worldNameInput.value) elements.worldNameInput.value = "world";
  elements.worldCreateBackdrop.hidden = false;
  window.requestAnimationFrame(() => {
    elements.worldNameInput.focus({ preventScroll: true });
    elements.worldNameInput.select();
  });
}

function closeWorldCreateDialog({ restoreFocus = true, force = false } = {}) {
  if (elements.worldCreateBackdrop.hidden || (state.worldCreateInFlight && !force)) return;
  elements.worldCreateBackdrop.hidden = true;
  const returnFocus = state.worldCreateReturnFocus || elements.worldTrigger;
  state.worldCreateReturnFocus = null;
  if (restoreFocus && returnFocus?.isConnected) returnFocus.focus({ preventScroll: true });
}

function setWorldCreateBusy(busy) {
  state.worldCreateInFlight = busy;
  elements.worldCreateDialog.setAttribute("aria-busy", busy ? "true" : "false");
  elements.worldNameInput.disabled = busy;
  elements.worldCreateCancel.disabled = busy;
  elements.worldCreateSubmit.disabled = busy;
  elements.worldCreateSubmitLabel.textContent = busy ? "Creating…" : "Create";
}

function showWorldCreateError(message) {
  elements.worldCreateError.textContent = message;
  elements.worldCreateError.hidden = false;
}

function validWorldName(name) {
  return (
    typeof name === "string"
    && name.trim().length > 0
    && Array.from(name).length <= 128
    && !name.includes("\n")
    && !name.includes("\r")
  );
}

async function submitWorldCreation(event) {
  event.preventDefault();
  if (state.worldCreateInFlight) return;
  const name = elements.worldNameInput.value;
  elements.worldCreateError.hidden = true;
  elements.worldCreateError.textContent = "";
  if (!validWorldName(name)) {
    showWorldCreateError("Enter a single-line world name of 1–128 characters.");
    elements.worldNameInput.focus();
    return;
  }

  setWorldCreateBusy(true);
  let created = null;
  try {
    created = await requestWorldCreation(name);
    state.knownWorlds = [
      ...state.knownWorlds.filter((world) => world.id !== created.id),
      { id: created.id, name: created.name, isCurrent: true },
    ].map((world) => ({ ...world, isCurrent: world.id === created.id }));
    state.currentWorldID = created.id;
    renderWorldPicker({
      worlds: state.knownWorlds,
      selectedWorldID: created.id,
      currentWorldID: created.id,
    });
    setWorldCreateBusy(false);
    elements.worldNameInput.value = "world";
    closeWorldCreateDialog({ restoreFocus: false, force: true });
    const opened = await restoreHumanViewForWorld(created.id, { historyMode: "replace" });
    elements.worldTrigger.focus({ preventScroll: true });
    announce(`${created.name} created.`);
    if (!opened) showToast("The world was created but could not be opened yet.");
  } catch (error) {
    if (error?.code === "session") {
      showWorldCreateError("The local session ended. Restart khoros web.");
    } else if (error?.code === "validation") {
      showWorldCreateError("Enter a single-line world name of 1–128 characters.");
    } else {
      showWorldCreateError("The world could not be created.");
    }
  } finally {
    if (!created) setWorldCreateBusy(false);
  }
}

function showAgentAddError(message) {
  elements.agentAddError.textContent = message;
  elements.agentAddError.hidden = false;
}

function selectedAgentOption() {
  return state.agentAddOptions.find((agent) => agent.id === state.selectedAgentID) || null;
}

function renderAgentChoice() {
  const options = Array.isArray(state.agentAddOptions) ? state.agentAddOptions : [];
  const available = options.filter((agent) => agent.state === "available");
  if (!available.some((agent) => agent.id === state.selectedAgentID)) {
    state.selectedAgentID = available[0]?.id || null;
  }
  const selected = selectedAgentOption();
  elements.agentChoiceMenu.replaceChildren();

  if (state.agentAddLoading) {
    elements.agentChoiceValue.textContent = "Loading agents…";
    elements.agentChoiceSymbol.hidden = true;
  } else if (selected) {
    elements.agentChoiceValue.textContent = selected.name;
    applySymbol(elements.agentChoiceSymbol, selected.visual);
    elements.agentChoiceSymbol.hidden = false;
  } else {
    elements.agentChoiceValue.textContent = options.length
      ? "No agent can be added"
      : "No agent identities";
    elements.agentChoiceSymbol.hidden = true;
  }

  elements.agentChoiceHint.textContent = state.agentAddLoading
    ? "Reading the user-owned agent catalog."
    : available.length
      ? "Choose a user-owned identity that can enter this World."
      : options.length
        ? "Every identity is already present here or assigned to another World."
        : "No user-owned agent identities are available.";

  for (const agent of options) {
    const eligible = agent.state === "available";
    const isSelected = agent.id === state.selectedAgentID;
    const row = node("button", "menu-row");
    row.type = "button";
    row.setAttribute("role", "menuitemradio");
    row.setAttribute("aria-checked", isSelected ? "true" : "false");
    if (!eligible) row.setAttribute("aria-disabled", "true");
    row.classList.toggle("is-selected", isSelected);
    const symbol = node("span", "agent-symbol");
    applySymbol(symbol, agent.visual);
    row.append(symbol);
    const copy = node("span", "row-copy");
    copy.append(node("span", "row-title", agent.name));
    copy.append(node("code", "row-subtitle identity-code", agent.id));
    row.append(copy);
    const stateLabel = isSelected
      ? "Selected"
      : agent.state === "present"
        ? "Present"
        : agent.state === "assignedElsewhere"
          ? "Another World"
          : "";
    row.append(node("span", "candidate-state", stateLabel));
    if (eligible) {
      row.addEventListener("click", () => {
        closeActiveSurface({ restoreFocus: false });
        state.selectedAgentID = agent.id;
        renderAgentChoice();
        elements.agentChoiceTrigger.focus({ preventScroll: true });
      });
    }
    elements.agentChoiceMenu.append(row);
  }

  const formDisabled = state.agentAddLoading || state.agentAddInFlight;
  elements.agentChoiceTrigger.disabled = formDisabled || options.length === 0;
  elements.agentCoordinateX.disabled = formDisabled;
  elements.agentCoordinateY.disabled = formDisabled;
  elements.agentAutoAdapt.disabled = formDisabled;
  elements.agentAddSubmit.disabled = formDisabled || !selected;
}

function setAgentAddLoading(loading) {
  state.agentAddLoading = loading;
  elements.agentAddDialog.setAttribute(
    "aria-busy",
    loading || state.agentAddInFlight ? "true" : "false",
  );
  renderAgentChoice();
}

function setAgentAddBusy(busy) {
  state.agentAddInFlight = busy;
  elements.agentAddDialog.setAttribute(
    "aria-busy",
    busy || state.agentAddLoading ? "true" : "false",
  );
  elements.agentAddCancel.disabled = busy;
  elements.agentAddSubmitLabel.textContent = busy ? "Adding…" : "Add agent";
  renderAgentChoice();
}

async function openAgentAddDialog() {
  const worldID = state.snapshot?.selectedWorldID;
  if (!isExactID(worldID)) return;
  closeActiveSurface({ restoreFocus: false });
  state.agentAddReturnFocus = elements.addAgentButton;
  state.agentAddWorldID = worldID;
  state.agentAddOptions = [];
  state.selectedAgentID = null;
  state.agentAddAutoAdapt = false;
  elements.agentAutoAdapt.setAttribute("aria-pressed", "false");
  elements.agentAutoAdapt.querySelector("img").hidden = true;
  elements.agentCoordinateX.value = "0";
  elements.agentCoordinateY.value = "0";
  elements.agentAddError.hidden = true;
  elements.agentAddError.textContent = "";
  elements.agentAddBackdrop.hidden = false;
  setAgentAddLoading(true);
  window.requestAnimationFrame(() => elements.agentAddDialog.focus({ preventScroll: true }));

  try {
    const result = await requestWorldAgentOptions(worldID);
    if (state.agentAddWorldID !== worldID || elements.agentAddBackdrop.hidden) return;
    state.agentAddOptions = result.agents;
    setAgentAddLoading(false);
    window.requestAnimationFrame(() => {
      const target = elements.agentChoiceTrigger.disabled
        ? elements.agentAddCancel
        : elements.agentChoiceTrigger;
      target.focus({ preventScroll: true });
    });
  } catch (error) {
    if (state.agentAddWorldID !== worldID || elements.agentAddBackdrop.hidden) return;
    setAgentAddLoading(false);
    showAgentAddError(
      error?.code === "session"
        ? "The local session ended. Restart khoros web."
        : "The agent catalog could not be opened.",
    );
    elements.agentAddCancel.focus({ preventScroll: true });
  }
}

function closeAgentAddDialog({ restoreFocus = true, force = false } = {}) {
  if (elements.agentAddBackdrop.hidden || (state.agentAddInFlight && !force)) return;
  if (state.activeSurface?.panel === elements.agentChoiceMenu) {
    closeActiveSurface({ restoreFocus: false });
  }
  elements.agentAddBackdrop.hidden = true;
  state.agentAddLoading = false;
  state.agentAddWorldID = null;
  state.agentAddOptions = [];
  state.selectedAgentID = null;
  const returnFocus = state.agentAddReturnFocus || elements.addAgentButton;
  state.agentAddReturnFocus = null;
  if (restoreFocus && returnFocus?.isConnected) returnFocus.focus({ preventScroll: true });
}

function parseCoordinateInput(value) {
  const text = String(value).trim();
  if (!/^-?(0|[1-9]\d*)$/.test(text)) return null;
  const numeric = Number(text);
  return Number.isSafeInteger(numeric) ? numeric : null;
}

async function submitAgentAddition(event) {
  event.preventDefault();
  if (state.agentAddInFlight || state.agentAddLoading) return;
  const worldID = state.agentAddWorldID;
  const agent = selectedAgentOption();
  const x = parseCoordinateInput(elements.agentCoordinateX.value);
  const y = parseCoordinateInput(elements.agentCoordinateY.value);
  elements.agentAddError.hidden = true;
  elements.agentAddError.textContent = "";
  if (!isExactID(worldID) || !agent || agent.state !== "available") {
    showAgentAddError("Choose an agent that can enter this World.");
    elements.agentChoiceTrigger.focus({ preventScroll: true });
    return;
  }
  if (x === null || y === null) {
    showAgentAddError("Enter complete integer coordinates for X and Y.");
    (x === null ? elements.agentCoordinateX : elements.agentCoordinateY).focus();
    return;
  }

  setAgentAddBusy(true);
  let added = null;
  try {
    added = await requestWorldAgentAddition({
      worldID,
      agentID: agent.id,
      x,
      y,
      autoAdapt: state.agentAddAutoAdapt,
    });
    setAgentAddBusy(false);
    closeAgentAddDialog({ restoreFocus: false, force: true });
    const route = currentRoute();
    const opened = await loadWorld({
      route,
      mode: state.following ? "follow-refresh" : "preserve-camera",
    });
    elements.addAgentButton.focus({ preventScroll: true });
    announce(`${added.name} added to this World.`);
    showToast(
      opened
        ? `${added.name} added at (${added.actual.x},${added.actual.y}).`
        : `${added.name} was added, but the World could not be refreshed yet.`,
    );
  } catch (error) {
    if (error?.code === "session") {
      showAgentAddError("The local session ended. Restart khoros web.");
    } else if (error?.code === "validation") {
      showAgentAddError("Choose a valid agent and complete integer coordinates.");
    } else if (error?.code === "conflict") {
      showAgentAddError("That agent is already present or belongs to another World.");
    } else {
      showAgentAddError("The agent could not be added.");
    }
  } finally {
    if (!added) setAgentAddBusy(false);
  }
}

function agentRow(agent) {
  const row = node("button", "sidebar-row agent-row");
  row.type = "button";
  row.dataset.agentId = agent.id;
  const selected = state.following && agent.id === state.followedAgentID;
  row.classList.toggle("is-selected", selected);
  row.setAttribute("aria-pressed", selected ? "true" : "false");
  const symbol = node("span", "agent-symbol");
  applySymbol(symbol, agent.visual);
  row.append(symbol);
  const copy = node("span", "row-copy");
  copy.append(node("span", "row-title", agent.name));
  copy.append(node("code", "row-subtitle", agent.path || agent.id));
  row.append(copy);
  row.append(node("span", "presence-dot"));
  row.setAttribute("aria-label", `${agent.name}, active agent`);
  row.addEventListener("click", () => focusAgent(agent.id));
  return row;
}

function orderedAgentLists(snapshot) {
  const primary = Array.isArray(snapshot?.primaryAgents) ? snapshot.primaryAgents : [];
  const others = Array.isArray(snapshot?.otherAgents) ? snapshot.otherAgents : [];
  const all = [...primary, ...others];
  const worldID = snapshot?.selectedWorldID;
  if (!isExactID(worldID)) return { primary, others };

  const byID = new Map(all.map((agent) => [agent.id, agent]));
  const previous = state.agentOrderByWorld.get(worldID) || [];
  const next = [
    ...previous.filter((agentID) => byID.has(agentID)),
    ...all.map((agent) => agent.id).filter((agentID) => !previous.includes(agentID)),
  ];
  state.agentOrderByWorld.set(worldID, next);
  const ordered = next.map((agentID) => byID.get(agentID)).filter(Boolean);
  return {
    primary: ordered.slice(0, 3),
    others: ordered.slice(3),
  };
}

function renderAgents(snapshot) {
  const { primary, others } = orderedAgentLists(snapshot);
  const all = [...primary, ...others];
  const worldID = snapshot?.selectedWorldID;
  const canExpand = isExactID(worldID) && all.length >= 3;
  if (!canExpand && isExactID(worldID)) state.expandedAgentWorlds.delete(worldID);
  const expanded = canExpand && state.expandedAgentWorlds.has(worldID);
  const visible = expanded ? all : primary;
  elements.primaryAgents.replaceChildren(...visible.map(agentRow));
  elements.agentsEmpty.hidden = all.length > 0;
  elements.allAgentsAnchor.hidden = !canExpand;
  elements.allAgentsLabel.textContent = `All ${all.length} agents`;
  elements.allAgentsTrigger.setAttribute("aria-expanded", expanded ? "true" : "false");
  elements.allAgentsTrigger.setAttribute(
    "aria-label",
    expanded ? "Collapse to three active agents" : `Show all ${all.length} active agents`,
  );
  elements.addAgentButton.disabled = !isExactID(snapshot?.selectedWorldID);
}

function renderHumanView() {
  const snapshot = state.snapshot;
  const worldID = snapshot?.selectedWorldID;
  const saved = state.following ? storedHumanView(worldID) : null;
  const path = state.following ? "Saved view" : (snapshot?.container?.path || "world");
  const x = Math.round(finiteCoordinate(saved?.cameraX ?? state.cameraX));
  const y = Math.round(finiteCoordinate(saved?.cameraY ?? state.cameraY));
  const zoom = Math.round((Number(saved?.zoom ?? state.zoom) || 1) * 100);
  elements.humanViewButton.classList.toggle("is-selected", !state.following);
  elements.humanViewButton.setAttribute("aria-pressed", state.following ? "false" : "true");
  elements.humanViewButton.setAttribute(
    "aria-label",
    `My view, ${path}, position ${x}, ${y}, zoom ${zoom} percent`,
  );
}

function stopFollowPolling() {
  window.clearTimeout(state.followTimer);
  state.followTimer = null;
  state.followGeneration += 1;
  state.followInFlight = false;
}

function leaveFollowForManualNavigation() {
  if (!state.following) return;
  stopFollowPolling();
  state.following = false;
  state.followedAgentID = null;
  updateStructuralPath();
  const world = state.snapshot?.selectedWorldID;
  const container = state.snapshot?.container?.id;
  if (isExactID(world)) {
    updateRoute(
      {
        world,
        container: isExactID(container) && container !== world ? container : null,
      },
      "replace",
    );
  }
  renderAgents(state.snapshot);
  renderHumanView();
}

async function restoreHumanViewForWorld(
  worldID = state.snapshot?.selectedWorldID,
  { returnFocus = null, historyMode = "push" } = {},
) {
  if (!isExactID(worldID)) return false;
  stopFollowPolling();
  state.following = false;
  state.followedAgentID = null;
  updateStructuralPath();
  const saved = storedHumanView(worldID) || {
    containerID: worldID,
    cameraX: 0,
    cameraY: 0,
    zoom: 1,
    keyboardCell: { x: 0, y: 0 },
  };
  const hasContainerHint = isExactID(saved.containerID) && saved.containerID !== worldID;
  const route = {
    world: worldID,
    container: hasContainerHint ? saved.containerID : null,
  };
  updateRoute(route, historyMode);
  let opened = await loadWorld({
    route,
    mode: "restore-human",
    camera: saved,
    suppressUnavailable: hasContainerHint,
  });
  if (!opened && hasContainerHint) {
    const safe = {
      containerID: worldID,
      cameraX: 0,
      cameraY: 0,
      zoom: 1,
      keyboardCell: { x: 0, y: 0 },
    };
    saveStoredHumanView(worldID, safe);
    updateRoute({ world: worldID }, "replace");
    opened = await loadWorld({ route: { world: worldID }, mode: "reset-human", camera: safe });
    if (opened) showToast("My view returned to this world's root.");
  }
  if (opened && returnFocus?.isConnected) returnFocus.focus({ preventScroll: true });
  return opened;
}

async function focusAgent(agentID) {
  const world = state.snapshot?.selectedWorldID;
  if (!isExactID(world) || !isExactID(agentID)) return;
  if (!state.following) saveHumanView();
  stopFollowPolling();
  state.following = true;
  state.followedAgentID = agentID;
  const generation = state.followGeneration;
  updateRoute({ world, focus: agentID });
  const opened = await loadWorld({ route: { world, focus: agentID }, mode: "follow" });
  if (!opened || generation !== state.followGeneration || !state.following) {
    await restoreHumanViewForWorld(world, { historyMode: "replace" });
    return;
  }
  scheduleFollowPoll(generation);
  announce(`Following ${agentName(agentID)}.`);
}

function scheduleFollowPoll(generation = state.followGeneration, delay = FOLLOW_INTERVAL_MS) {
  window.clearTimeout(state.followTimer);
  state.followTimer = null;
  if (!state.following || generation !== state.followGeneration || document.hidden) return;
  state.followTimer = window.setTimeout(() => pollFollow(generation), delay);
}

async function pollFollow(generation) {
  if (
    !state.following
    || state.followInFlight
    || generation !== state.followGeneration
    || document.hidden
  ) return;
  const world = state.snapshot?.selectedWorldID;
  const agentID = state.followedAgentID;
  if (!isExactID(world) || !isExactID(agentID)) return;
  state.followInFlight = true;
  try {
    const snapshot = await requestJSON(worldAPIPath({ world, focus: agentID }));
    if (
      generation !== state.followGeneration
      || !state.following
      || state.followedAgentID !== agentID
      || snapshot?.focusedAgentID !== agentID
    ) return;
    state.snapshot = snapshot;
    renderSnapshot("follow-refresh");
  } catch {
    if (generation === state.followGeneration && state.following) {
      announce("The followed agent is no longer available. Returning to My view.");
      await restoreHumanViewForWorld(world, { historyMode: "replace" });
    }
    return;
  } finally {
    if (generation === state.followGeneration) state.followInFlight = false;
  }
  scheduleFollowPoll(generation);
}

function agentName(agentID) {
  const agents = [
    ...(state.snapshot?.primaryAgents || []),
    ...(state.snapshot?.otherAgents || []),
  ];
  return agents.find((agent) => agent.id === agentID)?.name || "agent";
}

function renderInventory(snapshot) {
  const count = Number(snapshot?.inventoryObjectCount);
  const countLabel = Number.isFinite(count)
    ? `${count} source${count === 1 ? "" : "s"}`
    : "Global sources";
  elements.inventoryCount.textContent = countLabel;
  elements.inventoryShortcut.setAttribute("aria-label", `Inventory, ${countLabel}`);
}

async function renderPins() {
  const snapshotAtStart = state.snapshot;
  const worldID = snapshotAtStart?.selectedWorldID;
  const ids = pinnedIDs(worldID);
  elements.pinnedObjects.replaceChildren();
  if (!ids.length || !isExactID(worldID)) return;

  const direct = new Map((snapshotAtStart.objects || []).map((object) => [object.id, object]));
  const results = await Promise.all(
    ids.map(async (objectID) => {
      if (direct.has(objectID)) return { objectID, object: direct.get(objectID) };
      try {
        const response = await requestJSON(
          `/api/v1/object?world=${encodeURIComponent(worldID)}&object=${encodeURIComponent(objectID)}`,
        );
        return { objectID, object: response.object || null };
      } catch {
        return { objectID, object: null };
      }
    }),
  );
  if (state.snapshot !== snapshotAtStart) return;

  for (const result of results) {
    const row = node("button", "sidebar-row pinned-row");
    row.type = "button";
    const symbol = node("span", "row-icon identity-symbol");
    applySymbol(symbol, result.object?.visual);
    row.append(symbol);
    const copy = node("span", "row-copy");
    copy.append(node("span", "row-title", result.object?.name || "Unavailable object"));
    copy.append(node("code", "row-subtitle", result.objectID));
    row.append(copy);
    if (result.object) {
      row.setAttribute("aria-label", `Pinned object: ${result.object.name}`);
      row.addEventListener("click", () => openObject(result.objectID, row));
    } else {
      row.setAttribute("aria-label", "Unavailable pinned object. Activate to unpin.");
      row.addEventListener("click", () => {
        setPinned(worldID, result.objectID, false);
        renderPins();
        showToast("Unavailable object unpinned.");
      });
    }
    elements.pinnedObjects.append(row);
  }
}

function renderReports(snapshot) {
  const reports = Array.isArray(snapshot?.reports) ? snapshot.reports : [];
  elements.reportCount.textContent = `Showing ${reports.length} recent`;
  elements.reportList.replaceChildren();
  const latest = reports[0];
  const preview = latest?.title || latest?.body || "No reports";
  const hasUnread = Boolean(latest) && reportSeen(snapshot?.selectedWorldID) !== latest.id;
  elements.notificationPreview.textContent = preview;
  elements.notificationCue.hidden = !hasUnread;
  elements.notificationTrigger.setAttribute(
    "aria-label",
    `${hasUnread ? "New report available. " : "World reports. "}${preview}`,
  );

  if (!reports.length) {
    const empty = node("p", "sidebar-empty", "No recent object reports in this world.");
    elements.reportList.append(empty);
    return;
  }

  for (const report of reports) {
    const row = node("button", "report-row");
    row.type = "button";
    row.append(icon("bell", "", ""));
    const copy = node("span", "report-copy");
    copy.append(node("strong", "", report.title || report.type || "Object report"));
    copy.append(node("span", "", report.body || report.type || "Stored report"));
    row.append(copy);
    row.append(node("time", "report-time", relativeTime(report.timestamp)));
    row.addEventListener("click", () => {
      closeActiveSurface({ restoreFocus: false });
      markReportSeen(report);
      openReportDetail(report, elements.notificationTrigger);
    });
    elements.reportList.append(row);
  }
}

function openReportDetail(report, trigger) {
  if (!report || typeof report !== "object") return;
  openManagementDialog({
    title: report.title || report.type || "Object report",
    summary: `Stored ${relativeTime(report.timestamp)} · ${report.type || "object report"}`,
    trigger,
  });
  const detail = node("article", "report-detail");
  if (report.body) detail.append(node("p", "report-detail-body", report.body));
  const identity = node("dl", "native-detail-grid");
  identity.append(
    valueLine("Report ID", report.id, { mono: true }),
    valueLine("Type", report.type || "—", { mono: true }),
    valueLine("Recorded", compactDate(report.timestamp) || "Stored"),
  );
  detail.append(contentSection("Report", identity));
  const lineage = node("dl", "native-detail-grid");
  lineage.append(
    valueLine("World", report.worldID, { mono: true }),
    valueLine("Object", report.objectID, { mono: true }),
    valueLine("Inventory source", report.inventoryObjectID, { mono: true }),
    valueLine("Inventory revision", report.inventoryRevision === undefined ? "—" : String(report.inventoryRevision)),
    valueLine("Package", `${report.packageID || "—"}@${report.packageVersion || "—"}`, { mono: true }),
  );
  detail.append(contentSection("Lineage", lineage));
  const payload = report.payload && typeof report.payload === "object"
    ? renderData(report.payload, "payload")
    : node("p", "report-detail-empty", "No structured payload was stored.");
  detail.append(contentSection("Payload", payload));
  if (isExactID(report.objectID) && isExactID(report.worldID)) {
    const actions = node("div", "operation-actions");
    const object = node("button", "native-button");
    object.type = "button";
    object.append(icon("cube", "control-icon"), node("span", "", "Open object"));
    object.addEventListener("click", async () => {
      closeActionSheet({ restoreFocus: false });
      if (state.snapshot?.selectedWorldID !== report.worldID) {
        switchWebView("world", { historyMode: null });
        updateRoute({ world: report.worldID }, "push");
        const opened = await loadWorld({ route: { world: report.worldID }, mode: "preserve-camera" });
        if (!opened) return;
      }
      openObject(report.objectID, trigger);
    });
    actions.append(object);
    detail.append(actions);
  }
  elements.operationDetail.append(detail);
}

function relativeTime(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Stored";
  const seconds = Math.round((Date.now() - date.getTime()) / 1000);
  if (seconds < 60) return "Now";
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h`;
  return `${Math.floor(seconds / 86400)}d`;
}

function allVisibleAgents() {
  const snapshot = state.snapshot;
  if (!snapshot?.container) return [];
  const map = new Map();
  for (const agent of [...(snapshot.primaryAgents || []), ...(snapshot.otherAgents || [])]) {
    if (agent.containerID === snapshot.container.id) map.set(agent.id, agent);
  }
  return Array.from(map.values());
}

function screenPosition(coordinate) {
  const rect = elements.worldViewport.getBoundingClientRect();
  const cell = Number.parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--cell-size")) * state.zoom;
  const availableHeight = Math.max(0, rect.height - consoleOcclusionHeight());
  return {
    left: rect.width / 2 + (coordinate.x - state.cameraX) * cell,
    top: availableHeight / 2 + (coordinate.y - state.cameraY) * cell,
    cell,
  };
}

function renderWorld() {
  const snapshot = state.snapshot;
  if (snapshot?.state !== "available") return;
  const rect = elements.worldViewport.getBoundingClientRect();
  if (!rect.width || !rect.height) return;
  const baseCell = Number.parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--cell-size"));
  const cell = baseCell * state.zoom;
  const columns = Math.ceil(rect.width / cell) + 4;
  const availableHeight = Math.max(0, rect.height - consoleOcclusionHeight());
  const startX = Math.floor(state.cameraX - columns / 2);
  const endX = Math.ceil(state.cameraX + columns / 2);
  const halfUsableRows = availableHeight / (2 * cell);
  const startY = Math.ceil(state.cameraY - halfUsableRows + 0.5);
  const endY = Math.floor(state.cameraY + halfUsableRows - 0.5);
  const occupancy = new Map();
  for (const object of snapshot.objects || []) {
    const coordinate = getCoordinates(object);
    if (!coordinate) continue;
    const key = `${coordinate.x},${coordinate.y}`;
    const cell = occupancy.get(key) || { objects: [], agents: [] };
    cell.objects.push(object);
    occupancy.set(key, cell);
  }
  for (const agent of allVisibleAgents()) {
    const coordinate = getCoordinates(agent);
    if (!coordinate) continue;
    const key = `${coordinate.x},${coordinate.y}`;
    const cell = occupancy.get(key) || { objects: [], agents: [] };
    cell.agents.push(agent);
    occupancy.set(key, cell);
  }
  for (const cell of occupancy.values()) {
    cell.objects.sort((left, right) => (left.id < right.id ? -1 : left.id > right.id ? 1 : 0));
    cell.agents.sort((left, right) => (left.id < right.id ? -1 : left.id > right.id ? 1 : 0));
  }

  const cells = document.createDocumentFragment();
  for (let y = startY; y <= endY; y += 1) {
    for (let x = startX; x <= endX; x += 1) {
      const occupants = occupancy.get(`${x},${y}`) || { objects: [], agents: [] };
      cells.append(worldCell({ x, y }, occupants));
    }
  }
  elements.worldLayer.replaceChildren();
  elements.entityLayer.replaceChildren(cells);
  elements.worldViewport.classList.toggle("labels-hidden", !state.labels);
  elements.zoomIndicator.textContent = `${Math.round(state.zoom * 100)}%`;
  renderHumanView();
}

function worldCell(coordinate, occupants) {
  const control = node("button", "world-cell");
  control.type = "button";
  control.tabIndex = -1;
  control.dataset.x = String(coordinate.x);
  control.dataset.y = String(coordinate.y);
  const position = screenPosition(coordinate);
  control.style.left = `${position.left}px`;
  control.style.top = `${position.top}px`;
  control.style.setProperty("--world-zoom", String(state.zoom));

  const object = occupants.objects[0] || null;
  const representativeAgent = occupants.agents[0] || null;
  const held = representativeAgent?.primaryHeldObject || null;
  if (!object && !representativeAgent) {
    control.classList.add("is-empty");
    control.append(node("span", "grid-dot"));
  } else {
    control.classList.add("is-occupied");
    if (representativeAgent) {
      const agentColor = visualFor(representativeAgent.visual).color;
      control.classList.add("has-agent");
      control.style.setProperty("--agent-color", agentColor);
      if (held?.visual) {
        control.classList.add("agent-holding");
        control.style.setProperty("--agent-contrast", contrastColor(agentColor));
        const symbol = node("span", "cell-symbol held-object-symbol");
        applySymbol(symbol, held.visual);
        symbol.style.setProperty("--entity-color", contrastColor(agentColor));
        control.append(symbol);
      }
    }
    if (object && !held?.visual) {
      const symbol = node("span", "cell-symbol placed-object-symbol");
      applySymbol(symbol, object.visual);
      control.append(symbol);
    }
    if (object) control.append(node("span", "entity-label", object.name));
    if (occupants.agents.length > 1) {
      control.append(node("span", "cell-occupant-count", String(occupants.agents.length)));
    }
  }
  control.setAttribute(
    "aria-label",
    `Position (${coordinate.x},${coordinate.y}). ${descriptionForOccupants(occupants)}`,
  );
  control.addEventListener("pointerenter", () => {
    if (!state.pointerGesture?.dragging) setConsoleHover(coordinate);
  });
  control.addEventListener("pointerleave", () => {
    const live = state.consoleLiveCoordinate;
    if (live?.x === coordinate.x && live?.y === coordinate.y) setConsoleHover(null);
  });
  control.addEventListener("click", () => handleCellClick(coordinate, occupants, control));
  control.addEventListener("dblclick", (event) => {
    const objectToOpen = occupants.objects.length === 1 ? occupants.objects[0] : null;
    if (!objectToOpen?.hasContainer) return;
    cancelPendingObjectActivation();
    event.preventDefault();
    openContainerObject(objectToOpen);
  });
  return control;
}

function descriptionForOccupants(occupants) {
  const names = [
    ...occupants.objects.map((value) => `${value.name}, object`),
    ...occupants.agents.map((value) => {
      const holding = value.primaryHeldObject ? ", holding an object" : "";
      return `${value.name}, agent${holding}`;
    }),
  ];
  return names.length ? names.join(". ") : "Empty position";
}

function cancelPendingObjectActivation() {
  if (!state.pendingObjectActivation) return;
  window.clearTimeout(state.pendingObjectActivation.timer);
  state.pendingObjectActivation = null;
}

function shouldConsumeEmptyCellDismissal(activeSurface, target) {
  if (!(target instanceof Element)) return false;
  return activeSurface?.panel === elements.cellQuickMenu
    && activeSurface.trigger.classList.contains("is-occupied")
    && Boolean(target.closest(".world-cell.is-empty"));
}

function handleCellClick(coordinate, occupants, trigger) {
  if (state.suppressNextMapClick) return;
  cancelPendingObjectActivation();
  const object = occupants.objects.length === 1 ? occupants.objects[0] : null;
  const open = () => {
    state.pendingObjectActivation = null;
    openCellQuickMenu(coordinate, occupants, trigger);
  };
  if (object?.hasContainer) {
    state.pendingObjectActivation = {
      objectID: object.id,
      timer: window.setTimeout(open, OBJECT_CLICK_DELAY_MS),
    };
  } else {
    open();
  }
}

function quickMenuRow(iconName, label, action, meta = null) {
  const row = node("button", "menu-row");
  row.type = "button";
  row.setAttribute("role", "menuitem");
  row.append(icon(iconName));
  row.append(node("span", "row-title", label));
  if (meta) row.append(node("span", "menu-meta", meta));
  row.addEventListener("click", action);
  return row;
}

function cellMenuHeading(coordinate, title, visual = null) {
  const heading = node("div", "object-menu-heading");
  if (visual) {
    const symbol = node("span", "agent-symbol");
    applySymbol(symbol, visual);
    heading.append(symbol);
  } else {
    const marker = node("span", "row-icon empty-position-symbol");
    marker.append(node("span", "grid-dot"));
    heading.append(marker);
  }
  const copy = node("span", "row-copy");
  copy.append(node("strong", "row-title", title));
  copy.append(node("code", "row-subtitle", `(${coordinate.x},${coordinate.y})`));
  heading.append(copy);
  return heading;
}

function openCellQuickMenu(coordinate, occupants, trigger) {
  elements.cellQuickMenu.replaceChildren();
  const worldID = state.snapshot?.selectedWorldID;
  const object = occupants.objects.length === 1 ? occupants.objects[0] : null;
  if (object) {
    elements.cellQuickMenu.append(cellMenuHeading(coordinate, object.name, object.visual));
    elements.cellQuickMenu.append(
      quickMenuRow("arrow-square-out", "Open interface", () => {
        closeActiveSurface({ restoreFocus: false });
        openObject(object.id, trigger);
      }),
    );
    if (object.hasContainer) {
      elements.cellQuickMenu.append(
        quickMenuRow("globe", "Open container", () => {
          closeActiveSurface({ restoreFocus: false });
          openContainerObject(object);
        }),
      );
    }
    const isPinned = pinnedIDs(worldID).includes(object.id);
    elements.cellQuickMenu.append(
      quickMenuRow("push-pin", isPinned ? "Unpin object" : "Pin object", () => {
        setPinned(worldID, object.id, !isPinned);
        closeActiveSurface({ restoreFocus: false });
        renderPins();
        announce(`${object.name} ${isPinned ? "unpinned" : "pinned"}.`);
        trigger.focus({ preventScroll: true });
      }),
    );
  } else if (occupants.objects.length) {
    elements.cellQuickMenu.append(cellMenuHeading(coordinate, "Occupied position"));
    for (const placedObject of occupants.objects) {
      elements.cellQuickMenu.append(
        quickMenuRow("arrow-square-out", placedObject.name, () => {
          closeActiveSurface({ restoreFocus: false });
          openObject(placedObject.id, trigger);
        }, "Object"),
      );
    }
  } else {
    const title = occupants.agents.length ? "Occupied position" : "Empty position";
    const visual = occupants.agents.length === 1 ? occupants.agents[0].visual : null;
    elements.cellQuickMenu.append(cellMenuHeading(coordinate, title, visual));
  }
  for (const agent of occupants.agents) {
    elements.cellQuickMenu.append(
      quickMenuRow("crosshair", `Follow ${agent.name}`, () => {
        closeActiveSurface({ restoreFocus: false });
        focusAgent(agent.id);
      }, agent.primaryHeldObject ? "Holding" : "Active"),
    );
  }
  if (!occupants.objects.length && !occupants.agents.length) {
    elements.cellQuickMenu.append(
      quickMenuRow("crosshair", "Center view here", () => {
        closeActiveSurface({ restoreFocus: false });
        leaveFollowForManualNavigation();
        state.cameraX = coordinate.x;
        state.cameraY = coordinate.y;
        state.keyboardCell = { ...coordinate };
        renderWorld();
        saveHumanView();
        elements.worldViewport.focus({ preventScroll: true });
      }),
    );
  }
  const viewport = elements.worldViewport.getBoundingClientRect();
  const position = screenPosition(coordinate);
  const availableBottom = Math.max(232, viewport.height - consoleOcclusionHeight());
  elements.cellQuickMenu.style.left = `${Math.max(12, Math.min(viewport.width - 248, position.left + 18))}px`;
  elements.cellQuickMenu.style.top = `${Math.max(12, Math.min(availableBottom - 220, position.top - 12))}px`;
  trigger.setAttribute("aria-haspopup", "menu");
  trigger.setAttribute("aria-controls", "cellQuickMenu");
  openSurface(trigger, elements.cellQuickMenu);
}

function occupantsAt(coordinate) {
  const objects = (state.snapshot?.objects || []).filter((value) => {
    const item = getCoordinates(value);
    return item?.x === coordinate.x && item?.y === coordinate.y;
  });
  const agents = allVisibleAgents().filter((value) => {
    const item = getCoordinates(value);
    return item?.x === coordinate.x && item?.y === coordinate.y;
  });
  objects.sort((left, right) => (left.id < right.id ? -1 : left.id > right.id ? 1 : 0));
  agents.sort((left, right) => (left.id < right.id ? -1 : left.id > right.id ? 1 : 0));
  return { objects, agents };
}

function recenterOnFollow(announceChange = true) {
  const focused = [...(state.snapshot?.primaryAgents || []), ...(state.snapshot?.otherAgents || [])]
    .find((agent) => agent.id === state.followedAgentID);
  const coordinate = getCoordinates(focused) || { x: 0, y: 0 };
  state.cameraX = coordinate.x;
  state.cameraY = coordinate.y;
  state.keyboardCell = { ...coordinate };
  renderWorld();
  if (announceChange && focused) announce(`Recentered on ${focused.name}.`);
}

function setZoom(next, { manual = true } = {}) {
  if (manual) leaveFollowForManualNavigation();
  state.zoom = Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, next));
  elements.zoomIndicator.textContent = `${Math.round(state.zoom * 100)}%`;
  elements.zoomIndicator.classList.add("is-visible");
  window.clearTimeout(state.zoomTimer);
  state.zoomTimer = window.setTimeout(() => elements.zoomIndicator.classList.remove("is-visible"), 900);
  renderWorld();
  if (manual) saveHumanView();
}

function applyViewAction(action) {
  if (action === "world-actions") {
    openWorldActions();
    return;
  }
  if (action === "zoom-in") setZoom(state.zoom + 0.15);
  if (action === "zoom-out") setZoom(state.zoom - 0.15);
  if (action === "recenter") {
    void restoreHumanViewForWorld(state.snapshot?.selectedWorldID, { historyMode: "replace" });
  }
  if (action === "labels") {
    leaveFollowForManualNavigation();
    state.labels = !state.labels;
    const row = elements.viewMenu.querySelector("[data-view-action='labels']");
    row.setAttribute("aria-checked", state.labels ? "true" : "false");
    const marker = row.querySelector(".menu-check");
    marker.hidden = !state.labels;
    renderWorld();
    announce(`Object labels ${state.labels ? "shown" : "hidden"}.`);
  }
}

async function openObject(objectID, returnFocus) {
  const worldID = state.snapshot?.selectedWorldID;
  if (!isExactID(worldID) || !isExactID(objectID)) return;
  closeActiveSurface({ restoreFocus: false });
  state.inspectorReturnFocus = returnFocus || document.activeElement;
  try {
    const response = await requestJSON(
      `/api/v1/object?world=${encodeURIComponent(worldID)}&object=${encodeURIComponent(objectID)}`,
    );
    if (response?.state !== "available" || !response.object) {
      showToast("That exact object is no longer available.");
      return;
    }
    state.selectedObject = response;
    renderInspector(response);
    elements.inspectorBackdrop.hidden = false;
    elements.objectInspector.focus();
  } catch (error) {
    showToast(error?.code === "session" ? "The local web session ended." : "The object interface could not be read.");
  }
}

function renderInspector(response) {
  const object = response.object;
  elements.inspectorTitle.textContent = object.name || "Object";
  elements.inspectorType.textContent = object.type || "object";
  applySymbol(elements.inspectorSymbol, object.visual);
  elements.inspectorIdentity.replaceChildren();
  elements.inspectorIdentity.append(node("p", "identity-summary", object.summary || "No object summary."));
  elements.inspectorIdentity.append(node("code", "identity-code", object.id));
  if (object.path) elements.inspectorIdentity.append(node("code", "identity-code", object.path));

  const worldID = response.worldID || state.snapshot?.selectedWorldID;
  const isPinned = pinnedIDs(worldID).includes(object.id);
  const pinLabel = isPinned ? "Unpin object" : "Pin object";
  elements.pinObjectLabel.textContent = pinLabel;
  elements.pinObjectButton.setAttribute("aria-label", pinLabel);
  elements.pinObjectButton.dataset.pinned = isPinned ? "true" : "false";
  elements.openContainerButton.hidden = !object.hasContainer;

  const interfaceValue = response.interface && typeof response.interface === "object"
    ? response.interface
    : {};
  const sections = [{ id: "details", label: "Details", value: interfaceValue.base || object }];
  const declared = interfaceValue.object && typeof interfaceValue.object === "object"
    ? interfaceValue.object
    : {};
  const sectionRank = new Map(INTERFACE_SECTION_ORDER.map((key, index) => [key, index]));
  const declaredSections = Object.entries(declared).sort(([left], [right]) => {
    const leftRank = sectionRank.get(left) ?? INTERFACE_SECTION_ORDER.length;
    const rightRank = sectionRank.get(right) ?? INTERFACE_SECTION_ORDER.length;
    if (leftRank !== rightRank) return leftRank - rightRank;
    return left < right ? -1 : left > right ? 1 : 0;
  });
  for (const [key, value] of declaredSections) {
    sections.push({ id: key, label: formatKey(key), value });
  }
  if (sections.length === 1 && !interfaceValue.base) {
    sections[0].value = object;
  }

  const remembered = rememberedInspectorPage(worldID, object.id);
  const selectedSection = sections.find((section) => section.id === remembered) || sections[0];
  elements.inspectorNav.replaceChildren();
  for (const [index, section] of sections.entries()) {
    const button = node("button", "inspector-nav-button");
    button.type = "button";
    button.id = `inspectorTab${index}`;
    button.dataset.sectionId = section.id;
    button.setAttribute("role", "tab");
    button.setAttribute("aria-controls", "inspectorContent");
    const selected = section === selectedSection;
    button.setAttribute("aria-selected", selected ? "true" : "false");
    button.tabIndex = selected ? 0 : -1;
    if (selected) button.classList.add("is-selected");
    button.append(icon(index === 0 ? "info" : "file-text"));
    button.append(node("span", "", section.label));
    button.addEventListener("click", () => {
      selectInspectorSection(section, button, worldID, object.id);
    });
    button.addEventListener("keydown", (event) => {
      const tabs = Array.from(elements.inspectorNav.querySelectorAll("[role='tab']"));
      const current = tabs.indexOf(button);
      let next = null;
      if (event.key === "ArrowRight") next = tabs[(current + 1) % tabs.length];
      if (event.key === "ArrowLeft") next = tabs[(current - 1 + tabs.length) % tabs.length];
      if (event.key === "Home") next = tabs[0];
      if (event.key === "End") next = tabs[tabs.length - 1];
      if (next) {
        event.preventDefault();
        next.focus();
        next.click();
      }
    });
    elements.inspectorNav.append(button);
  }
  const selectedButton = elements.inspectorNav.querySelector("[aria-selected='true']");
  renderInterfaceSection(selectedSection, selectedButton);
}

function selectInspectorSection(section, button, worldID, objectID) {
  for (const sibling of elements.inspectorNav.children) {
    const selected = sibling === button;
    sibling.classList.toggle("is-selected", selected);
    sibling.setAttribute("aria-selected", selected ? "true" : "false");
    sibling.tabIndex = selected ? 0 : -1;
  }
  rememberInspectorPage(worldID, objectID, section.id);
  renderInterfaceSection(section, button);
}

function renderInterfaceSection(section, tab = null) {
  elements.inspectorContent.replaceChildren();
  elements.inspectorContent.setAttribute("role", "tabpanel");
  elements.inspectorContent.tabIndex = 0;
  if (tab?.id) elements.inspectorContent.setAttribute("aria-labelledby", tab.id);
  const heading = node("div", "interface-heading");
  const copy = node("div");
  copy.append(node("h2", "", section.label));
  copy.append(
    node(
      "p",
      "",
      section.id === "details"
        ? "Runtime-owned identity, location, lineage, and available management contract."
        : "Declared by this exact object’s structured human-management interface.",
    ),
  );
  heading.append(copy);
  const exactObject = state.selectedObject?.object;
  const exactWorldID = state.selectedObject?.worldID || state.snapshot?.selectedWorldID;
  const exactManagement = state.selectedObject?.interface?.object || {};
  const hostPathRestricted = managementContractUsesHostPaths(exactManagement);
  if (section.id === "details" && isExactID(exactObject?.id) && exactObject.canMove === true) {
    const move = node("button", "native-button");
    move.type = "button";
    move.append(icon("arrow-square-out", "control-icon"), node("span", "", "Move"));
    move.addEventListener("click", () => openContextAction(
      NATIVE_ACTION_CANDIDATES.worldObjectMove,
      { label: "Move object", prefill: { objectID: exactObject.id }, trigger: move },
    ));
    heading.append(move);
  } else {
    const labels = {
      fields: "Declared fields",
      actions: "Object actions",
      views: "Object views",
      reports: "Object reports",
    };
    heading.append(node("span", "read-only-badge", labels[section.id] || "Object interface"));
  }
  elements.inspectorContent.append(heading);

  if (
    section.value === null
    || section.value === undefined
    || (Array.isArray(section.value) && section.value.length === 0)
    || (typeof section.value === "object" && !Array.isArray(section.value) && Object.keys(section.value).length === 0)
  ) {
    elements.inspectorContent.append(
      node("div", "empty-interface", "This object declares no entries for this section."),
    );
    return;
  }
  if (section.id === "fields") {
    elements.inspectorContent.append(renderManagementFields({
      scope: "world",
      source: exactObject,
      entries: section.value,
    }));
    return;
  }
  if (section.id === "actions") {
    elements.inspectorContent.append(renderManagementActions({
      scope: "world",
      source: exactObject,
      worldID: exactWorldID,
      entries: section.value,
      hostPathRestricted,
    }));
    return;
  }
  if (section.id === "views") {
    elements.inspectorContent.append(renderManagementViews({
      scope: "world",
      source: exactObject,
      worldID: exactWorldID,
      entries: section.value,
      hostPathRestricted,
    }));
    return;
  }
  if (section.id === "reports") {
    elements.inspectorContent.append(renderManagementReports(section.value));
    return;
  }
  elements.inspectorContent.append(renderData(section.value, section.id));
}

function renderData(value, key = "value", depth = 0) {
  if (Array.isArray(value)) {
    const list = node("div", "data-array");
    for (const item of value) {
      const wrapper = node("div", "array-item");
      wrapper.append(renderData(item, key, depth + 1));
      list.append(wrapper);
    }
    return list;
  }

  if (value !== null && typeof value === "object") {
    const group = node("div", depth > 0 ? "data-group" : "data-tree");
    for (const [childKey, childValue] of Object.entries(value)) {
      const row = node("div", "data-row");
      row.append(node("span", "data-key", formatKey(childKey)));
      const cell = node("div", "data-value");
      if (isCodeValue(childKey, childValue)) cell.classList.add("is-code");
      cell.append(renderData(childValue, childKey, depth + 1));
      row.append(cell);
      group.append(row);
    }
    return group;
  }

  const primitive = node("span");
  if (value === null) primitive.textContent = "Unavailable";
  else if (typeof value === "boolean") primitive.textContent = value ? "Yes" : "No";
  else primitive.textContent = String(value);
  return primitive;
}

function isCodeValue(key, value) {
  const normalized = String(key).toLowerCase();
  return (
    normalized.includes("id")
    || normalized.includes("type")
    || normalized.includes("package")
    || normalized.includes("coordinate")
    || normalized.includes("path")
    || (typeof value === "string" && ID_PATTERN.test(value))
  );
}

function closeInspector() {
  if (elements.inspectorBackdrop.hidden) return;
  elements.inspectorBackdrop.hidden = true;
  state.selectedObject = null;
  const returnFocus = state.inspectorReturnFocus;
  state.inspectorReturnFocus = null;
  if (returnFocus?.isConnected) returnFocus.focus({ preventScroll: true });
}

function toggleSelectedPin() {
  const response = state.selectedObject;
  const object = response?.object;
  const worldID = response?.worldID || state.snapshot?.selectedWorldID;
  if (!isExactID(worldID) || !isExactID(object?.id)) return;
  const shouldPin = elements.pinObjectButton.dataset.pinned !== "true";
  setPinned(worldID, object.id, shouldPin);
  elements.pinObjectButton.dataset.pinned = shouldPin ? "true" : "false";
  const pinLabel = shouldPin ? "Unpin object" : "Pin object";
  elements.pinObjectLabel.textContent = pinLabel;
  elements.pinObjectButton.setAttribute("aria-label", pinLabel);
  renderPins();
  announce(`${object.name} ${shouldPin ? "pinned" : "unpinned"}.`);
}

async function openSelectedContainer() {
  const object = state.selectedObject?.object;
  if (!object) return;
  closeInspector();
  await openContainerObject(object);
}

async function openContainerObject(object) {
  const world = state.snapshot?.selectedWorldID;
  if (!isExactID(world) || !isExactID(object?.id) || !object.hasContainer) return false;
  cancelPendingObjectActivation();
  leaveFollowForManualNavigation();
  updateRoute({ world, container: object.id });
  const opened = await loadWorld({
    route: { world, container: object.id },
    mode: "reset-human",
  });
  if (opened) {
    saveHumanView();
    announce(`Opened ${object.name}.`);
  }
  return opened;
}

function trapModalFocus(event, container) {
  const controls = Array.from(
    container.querySelectorAll(
      "button:not([disabled]), input:not([disabled]), a[href], [tabindex]:not([tabindex='-1'])",
    ),
  ).filter((control) => !control.hidden && control.getClientRects().length > 0);
  if (!controls.length) return;
  const first = controls[0];
  const last = controls[controls.length - 1];
  const active = document.activeElement;
  if (event.shiftKey && (active === first || !container.contains(active))) {
    event.preventDefault();
    last.focus();
  } else if (!event.shiftKey && (active === last || !container.contains(active))) {
    event.preventDefault();
    first.focus();
  }
}

function normalizedCapability(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const views = [...ROUTABLE_WEB_VIEWS, "help"];
  if (typeof raw.id !== "string" || raw.id.length < 1 || raw.id.length > 256) return null;
  if (!views.includes(raw.view)) return null;
  const fields = Array.isArray(raw.fields) ? raw.fields.map((field) => {
    if (!field || typeof field !== "object" || Array.isArray(field)) return null;
    if (typeof field.id !== "string" || !field.id || field.id.length > 128) return null;
    const choices = Array.isArray(field.choices)
      ? field.choices.filter((choice) => typeof choice === "string" && choice.length <= 1024).slice(0, 256)
      : [];
    return {
      id: field.id,
      label: typeof field.label === "string" && field.label ? field.label : formatKey(field.id),
      help: typeof field.help === "string" ? field.help : "",
      syntax: typeof field.syntax === "string" ? field.syntax : "text",
      cardinality: typeof field.cardinality === "string" ? field.cardinality : "optional",
      completion: typeof field.completion === "string" ? field.completion : "",
      historyPolicy: typeof field.historyPolicy === "string" ? field.historyPolicy : "omit",
      defaultValue: typeof field.defaultValue === "string" ? field.defaultValue : "",
      choices,
    };
  }).filter(Boolean) : [];
  return {
    id: raw.id,
    command: typeof raw.command === "string" && raw.command ? raw.command : raw.id,
    summary: typeof raw.summary === "string" ? raw.summary : "",
    view: raw.view,
    section: typeof raw.section === "string" && raw.section ? raw.section : "Actions",
    scope: typeof raw.scope === "string" && raw.scope ? raw.scope : "global",
    mode: typeof raw.mode === "string" && raw.mode ? raw.mode : "form",
    enabled: raw.enabled !== false,
    fields,
    refreshTargets: Array.isArray(raw.refreshTargets)
      ? raw.refreshTargets.filter((value) => typeof value === "string").slice(0, 64)
      : [],
    successTestID: typeof raw.successTestID === "string" ? raw.successTestID : "",
    failureTestID: typeof raw.failureTestID === "string" ? raw.failureTestID : "",
  };
}

function rememberWorldRoute() {
  const route = currentRoute();
  state.lastWorldRoute = {
    world: route.world || state.snapshot?.selectedWorldID || null,
    container: route.container || state.snapshot?.container?.id || null,
  };
}

function cancelWebActivity() {
  closeWebCombobox();
  closeWebAutocomplete();
  if (state.webRequest) state.webRequest.abort();
  state.webRequest = null;
  if (state.streamController) state.streamController.abort();
  state.streamController = null;
}

function clearSensitiveFields() {
  for (const field of elements.operationDetail.querySelectorAll("input[type='password']")) field.value = "";
  state.privateRevealed = false;
}

function cardinalityInfo(field) {
  const value = field.cardinality.toLocaleLowerCase();
  return {
    required: value.includes("required") || value === "one" || value === "1" || value.includes("1.."),
    repeated: value.includes("repeat") || value.includes("many") || value.includes("*") || value.includes("..n"),
  };
}

function inputKind(field, descriptor) {
  const syntax = `${field.id} ${field.label} ${field.syntax} ${field.completion}`.toLocaleLowerCase();
  if (descriptor.mode === "secret" && /secret|token|password|credential/.test(`${field.id} ${syntax}`)) return "secret";
  if (/secret|password/.test(syntax)) return "secret";
  if (/bool|flag|switch/.test(syntax)) return "boolean";
  if (/integer|int|number/.test(syntax)) return "integer";
  if (/url|uri|file-or-url/.test(syntax)) return "url";
  if (/file|upload/.test(syntax)) return "file";
  return "text";
}

function closeWebAutocomplete() {
  const active = state.webAutocomplete;
  if (!active) return;
  window.clearTimeout(active.timer);
  active.controller?.abort();
  active.menu.hidden = true;
  active.input.setAttribute("aria-expanded", "false");
  state.webAutocomplete = null;
}

function existingWebFields(form) {
  const fields = {};
  for (const control of form.querySelectorAll("[data-field-id]")) {
    if (!control.name || control.type === "password" || control.type === "file") continue;
    let values = [];
    if (control.type === "checkbox") {
      if (control.checked) values = ["true"];
    } else if (control.dataset.repeated === "true") {
      values = String(control.value || "").split(/\r?\n/).map((value) => value.trim()).filter(Boolean);
    } else {
      const value = String(control.value || "").trim();
      if (value) values = [value];
    }
    if (values.length) fields[control.name] = values;
  }
  return fields;
}

function webAutocompleteControl(form, descriptor, field) {
  const root = node("div", "web-autocomplete");
  const input = node("input", "web-input");
  input.type = inputKind(field, descriptor) === "integer" ? "number" : "text";
  input.value = field.defaultValue;
  input.autocomplete = "off";
  input.spellcheck = false;
  input.setAttribute("role", "combobox");
  input.setAttribute("aria-autocomplete", "list");
  input.setAttribute("aria-expanded", "false");
  const listID = `completion-${descriptor.id}-${field.id}`.replace(/[^a-zA-Z0-9_-]/g, "-");
  input.setAttribute("aria-controls", listID);
  const menu = node("div", "web-autocomplete-menu floating-menu");
  menu.id = listID;
  menu.role = "listbox";
  menu.hidden = true;

  const choose = (option) => {
    input.value = option.dataset.completionValue || "";
    input.dispatchEvent(new Event("change", { bubbles: true }));
    closeWebAutocomplete();
    input.focus({ preventScroll: true });
  };

  const render = (values) => {
    menu.replaceChildren();
    for (const item of values.slice(0, 64)) {
      if (!item || typeof item.value !== "string") continue;
      const option = node("button", "menu-row menu-row-text-only web-autocomplete-option");
      option.type = "button";
      option.role = "option";
      option.dataset.completionValue = item.value;
      option.append(
        node("span", "ellipsis", typeof item.label === "string" ? item.label : item.value),
        item.label && item.label !== item.value ? node("code", "completion-value", item.value) : node("span"),
      );
      option.addEventListener("pointerdown", (event) => event.preventDefault());
      option.addEventListener("click", () => choose(option));
      menu.append(option);
    }
    menu.hidden = !menu.childElementCount;
    input.setAttribute("aria-expanded", menu.hidden ? "false" : "true");
  };

  const complete = () => {
    closeWebAutocomplete();
    const active = { root, input, menu, timer: null, controller: null };
    state.webAutocomplete = active;
    active.timer = window.setTimeout(async () => {
      const controller = new AbortController();
      active.controller = controller;
      const worldValue = form.elements.namedItem("__worldID")?.value;
      try {
        const response = await window.fetch("/api/v1/web/completions", {
          method: "POST",
          credentials: "same-origin",
          headers: { Accept: "application/json", "Content-Type": "application/json" },
          body: JSON.stringify({
            operationID: descriptor.id,
            fieldID: field.id,
            source: input.value,
            ...(isExactID(worldValue) ? { worldID: worldValue } : {}),
            fields: existingWebFields(form),
          }),
          signal: controller.signal,
        });
        if (!response.ok || state.webAutocomplete !== active) return;
        const payload = await response.json();
        render(Array.isArray(payload?.values) ? payload.values : []);
      } catch (error) {
        if (error?.name !== "AbortError" && state.webAutocomplete === active) render([]);
      }
    }, 120);
  };

  input.addEventListener("focus", complete);
  input.addEventListener("input", complete);
  input.addEventListener("keydown", (event) => {
    const options = Array.from(menu.querySelectorAll(".web-autocomplete-option"));
    const current = options.indexOf(document.activeElement);
    if (event.key === "Escape") {
      closeWebAutocomplete();
      return;
    }
    if (event.key === "ArrowDown" && options.length) {
      event.preventDefault();
      options[Math.max(0, current + 1)]?.focus({ preventScroll: true });
    }
    if (event.key === "ArrowUp" && options.length) {
      event.preventDefault();
      options[Math.max(0, current - 1)]?.focus({ preventScroll: true });
    }
  });
  menu.addEventListener("keydown", (event) => {
    const options = Array.from(menu.querySelectorAll(".web-autocomplete-option"));
    const current = options.indexOf(document.activeElement);
    if (event.key === "ArrowDown") {
      event.preventDefault();
      options[(current + 1) % options.length]?.focus({ preventScroll: true });
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      options[(current - 1 + options.length) % options.length]?.focus({ preventScroll: true });
    } else if (event.key === "Enter" && document.activeElement?.dataset.completionValue) {
      event.preventDefault();
      choose(document.activeElement);
    } else if (event.key === "Escape") {
      event.preventDefault();
      closeWebAutocomplete();
      input.focus({ preventScroll: true });
    }
  });
  root.append(input, menu);
  return { root, input };
}

function isWorldFieldID(value) {
  return /^(world|worldid|world-id|world_id)$/i.test(value);
}

function closeWebCombobox({ restoreFocus = false } = {}) {
  const active = state.webCombobox;
  if (!active) return;
  active.menu.hidden = true;
  active.trigger.setAttribute("aria-expanded", "false");
  state.webCombobox = null;
  if (restoreFocus && active.trigger.isConnected) active.trigger.focus({ preventScroll: true });
}

function webChoiceControl({ name, choices, value = "", placeholder = "Choose an option", label }) {
  const root = node("div", "web-combobox");
  const input = node("input");
  input.type = "hidden";
  input.name = name;
  input.value = choices.some((choice) => choice.value === value) ? value : "";

  const trigger = node("button", "web-combobox-trigger");
  trigger.type = "button";
  trigger.setAttribute("aria-haspopup", "listbox");
  trigger.setAttribute("aria-expanded", "false");
  trigger.setAttribute("aria-label", label);
  const triggerValue = node("span", "web-combobox-value");
  const chevron = icon("caret-down", "control-icon chevron");
  trigger.append(triggerValue, chevron);

  const menu = node("div", "web-combobox-menu floating-menu");
  menu.role = "listbox";
  menu.hidden = true;

  const update = (nextValue) => {
    input.value = nextValue;
    const selected = choices.find((choice) => choice.value === nextValue);
    triggerValue.textContent = selected?.label || placeholder;
    trigger.classList.toggle("is-placeholder", !selected);
    trigger.title = selected?.title || selected?.value || "";
    for (const option of menu.querySelectorAll("[data-choice-value]")) {
      const isSelected = option.dataset.choiceValue === nextValue;
      option.setAttribute("aria-selected", isSelected ? "true" : "false");
      option.classList.toggle("is-selected", isSelected);
      option.querySelector(".menu-check").hidden = !isSelected;
    }
    input.dispatchEvent(new Event("change", { bubbles: true }));
  };

  for (const choice of choices) {
    const option = node("button", "menu-row menu-row-text-only web-combobox-option");
    option.type = "button";
    option.role = "option";
    option.dataset.choiceValue = choice.value;
    option.append(node("span", "ellipsis", choice.label), icon("check", "menu-check", "Selected"));
    option.addEventListener("click", () => {
      update(choice.value);
      closeWebCombobox({ restoreFocus: true });
    });
    menu.append(option);
  }

  const open = () => {
    closeWebCombobox();
    menu.hidden = false;
    trigger.setAttribute("aria-expanded", "true");
    state.webCombobox = { root, trigger, menu };
    const selected = menu.querySelector("[aria-selected='true']");
    (selected || menu.querySelector(".web-combobox-option"))?.focus({ preventScroll: true });
  };
  trigger.addEventListener("click", () => {
    if (state.webCombobox?.root === root) closeWebCombobox({ restoreFocus: true });
    else open();
  });
  trigger.addEventListener("keydown", (event) => {
    if (!["ArrowDown", "ArrowUp", "Enter", " "].includes(event.key)) return;
    event.preventDefault();
    open();
  });
  menu.addEventListener("keydown", (event) => {
    const options = Array.from(menu.querySelectorAll(".web-combobox-option"));
    const current = options.indexOf(document.activeElement);
    let target = null;
    if (event.key === "ArrowDown") target = options[(current + 1 + options.length) % options.length];
    if (event.key === "ArrowUp") target = options[(current - 1 + options.length) % options.length];
    if (event.key === "Home") target = options[0];
    if (event.key === "End") target = options[options.length - 1];
    if (event.key === "Escape") {
      event.preventDefault();
      closeWebCombobox({ restoreFocus: true });
      return;
    }
    if (!target) return;
    event.preventDefault();
    target.focus({ preventScroll: true });
  });

  root.append(input, trigger, menu);
  update(input.value);
  return { root, input };
}

function appendWorldField(form, descriptor) {
  const exactWorldScope = descriptor.scope.toLocaleLowerCase().includes("world");
  const alreadyDeclared = descriptor.fields.some((field) => isWorldFieldID(field.id));
  if (!exactWorldScope || alreadyDeclared) return;
  const wrap = node("div", "generated-field");
  const header = node("span", "generated-field-header");
  const lockedWorldID = isExactID(state.actionWorldLock) ? state.actionWorldLock : null;
  header.append(node("span", "field-label", "World"), node("span", "field-cardinality", lockedWorldID ? "Bound · action only" : "Required · action only"));
  wrap.append(header);
  if (lockedWorldID) {
    const locked = node("div", "action-world-lock");
    const name = state.knownWorlds.find((world) => world.id === lockedWorldID)?.name || "Bound World";
    const input = node("input");
    input.type = "hidden";
    input.name = "__worldID";
    input.value = lockedWorldID;
    input.required = true;
    locked.append(node("span", "", name), node("code", "", lockedWorldID), input);
    wrap.append(locked);
  } else if (state.knownWorlds.length) {
    const choices = state.knownWorlds.map((world) => ({
      value: world.id,
      label: world.name,
      title: `${world.name} · ${world.id}`,
    }));
    const choice = webChoiceControl({
      name: "__worldID",
      choices,
      value: choices.some((item) => item.value === state.snapshot?.selectedWorldID)
        ? state.snapshot.selectedWorldID
        : choices[0].value,
      placeholder: "Choose World",
      label: "Choose the exact World for this action",
    });
    choice.input.required = true;
    wrap.append(choice.root);
  } else {
    const input = node("input", "web-input");
    input.name = "__worldID";
    input.required = true;
    input.autocomplete = "off";
    input.placeholder = "Exact 32-character World ID";
    wrap.append(input);
  }
  wrap.append(node("span", "field-hint", lockedWorldID
    ? "This source is bound to this exact World."
    : "This selection applies only to this action and does not change the World workspace."));
  form.append(wrap);
}

function appendGeneratedField(form, descriptor, field) {
  const cardinality = cardinalityInfo(field);
  const kind = inputKind(field, descriptor);
  const wrap = node("div", "generated-field");
  wrap.dataset.fieldId = field.id;
  const header = node("span", "generated-field-header");
  header.append(
    node("span", "field-label", field.label),
    node("span", "field-cardinality", `${cardinality.required ? "Required" : "Optional"}${cardinality.repeated ? " · repeatable" : ""}`),
  );
  wrap.append(header);
  let control;
  if (isWorldFieldID(field.id)) {
    const lockedWorldID = isExactID(state.actionWorldLock) ? state.actionWorldLock : null;
    if (lockedWorldID) {
      const locked = node("div", "action-world-lock");
      const name = state.knownWorlds.find((world) => world.id === lockedWorldID)?.name || "Bound World";
      control = node("input");
      control.type = "hidden";
      control.value = lockedWorldID;
      locked.append(node("span", "", name), node("code", "", lockedWorldID), control);
      wrap.append(locked);
    } else {
      const choices = field.choices.length
      ? field.choices.map((value) => ({ value, label: value, title: value }))
      : state.knownWorlds.map((world) => ({ value: world.id, label: world.name, title: `${world.name} · ${world.id}` }));
      if (!cardinality.required) {
        choices.unshift({ value: "", label: "Not set", title: "" });
      }
      if (!choices.length) {
        control = node("input", "web-input");
        control.placeholder = "Exact 32-character World ID";
        control.value = field.defaultValue;
        control.autocomplete = "off";
        wrap.append(control);
      } else {
        const choice = webChoiceControl({
          name: field.id,
          choices,
          value: field.defaultValue || state.snapshot?.selectedWorldID || choices[0].value,
          placeholder: "Choose World",
          label: `Choose ${field.label}`,
        });
        control = choice.input;
        wrap.append(choice.root);
      }
    }
  } else if (kind === "boolean") {
    const toggle = node("label", "boolean-field");
    control = node("input");
    control.type = "checkbox";
    toggle.append(control, node("span", "", field.help || field.label));
    wrap.append(toggle);
  } else if (field.choices.length) {
    const choices = field.choices.map((value) => ({ value, label: value, title: value }));
    if (!cardinality.required) {
      choices.unshift({ value: "", label: "Not set", title: "" });
    }
    const choice = webChoiceControl({
      name: field.id,
      choices,
      value: field.defaultValue || choices[0].value,
      placeholder: `Choose ${field.label}`,
      label: `Choose ${field.label}`,
    });
    control = choice.input;
    wrap.append(choice.root);
  } else if (
    field.completion
    && !["none", "file-or-url"].includes(field.completion)
    && !cardinality.repeated
  ) {
    const autocomplete = webAutocompleteControl(form, descriptor, field);
    control = autocomplete.input;
    wrap.append(autocomplete.root);
  } else if (cardinality.repeated) {
    control = node("textarea", "web-textarea");
    control.placeholder = "One value per line";
    control.value = field.defaultValue;
    wrap.append(control);
  } else {
    control = node("input", "web-input");
    control.type = kind === "secret" ? "password" : kind === "integer" ? "number" : kind === "url" ? "url" : kind === "file" ? "file" : "text";
    if (kind === "integer") control.step = "1";
    if (kind !== "file" && kind !== "secret") control.value = field.defaultValue;
    control.autocomplete = kind === "secret" ? "new-password" : "off";
    control.spellcheck = false;
    wrap.append(control);
  }
  control.name = field.id;
  control.dataset.fieldId = field.id;
  control.dataset.fieldKind = kind;
  control.dataset.repeated = cardinality.repeated ? "true" : "false";
  control.required = cardinality.required && kind !== "boolean";
  if (field.help && kind !== "boolean") wrap.append(node("span", "field-hint", field.help));
  form.append(wrap);
}

function collectWebPayload(form, descriptor) {
  const fields = {};
  let secret = null;
  let worldID = null;
  const worldControl = form.elements.namedItem("__worldID");
  if (worldControl) {
    const candidate = String(worldControl.value || "").trim();
    if (!isExactID(candidate)) throw new Error("Choose a valid exact World.");
    worldID = candidate;
  }
  for (const field of descriptor.fields) {
    const control = form.elements.namedItem(field.id);
    if (!control) continue;
    const kind = control.dataset.fieldKind;
    if (kind === "file") {
      if (control.files?.length) throw new Error("Browser file transport is not connected for this action yet.");
      continue;
    }
    let values = [];
    if (kind === "boolean") {
      if (control.checked) values = ["true"];
    } else if (control.dataset.repeated === "true") {
      values = String(control.value).split(/\r?\n/).map((value) => value.trim()).filter(Boolean);
    } else {
      const value = String(control.value || "").trim();
      if (value) values = [value];
    }
    const info = cardinalityInfo(field);
    if (info.required && !values.length) throw new Error(`${field.label} is required.`);
    if (kind === "integer" && values.some((value) => !/^-?\d+$/.test(value))) throw new Error(`${field.label} must be an integer.`);
    if (kind === "url" && values.some((value) => {
      if (descriptor.id === "inventoryInstall" && /^builtin:[a-z0-9][a-z0-9-]*$/i.test(value)) return false;
      try {
        const url = new URL(value);
        return url.protocol !== "https:" || !url.hostname || Boolean(url.username || url.password);
      } catch { return true; }
    })) throw new Error(
      descriptor.id === "inventoryInstall"
        ? `${field.label} must be a trusted built-in package or HTTPS URL.`
        : `${field.label} must be an HTTPS URL.`,
    );
    if (kind === "secret") {
      secret = values[0] || "";
      continue;
    }
    if (isWorldFieldID(field.id)) {
      const candidate = values[0] || "";
      if (candidate && !isExactID(candidate)) throw new Error(`${field.label} must be an exact World ID.`);
    }
    if (values.length) fields[field.id] = values;
  }
  return { operationID: descriptor.id, ...(worldID ? { worldID } : {}), fields, secret };
}

function webErrorMessage(status) {
  if (status === 401 || status === 403) return "Session expired. Restart khoros web and reopen the exact launch link it prints.";
  if (status === 409) return "The requested resource is busy or changed. Refresh the action context and try again.";
  if (status === 410) return "The prepared action expired, was already used, or its product state changed. Prepare it again.";
  if (status === 400 || status === 422) return "The form or action context is invalid. Review the fields and try again.";
  if (status === 413) return "The request is too large for the mikrokhoros Web boundary.";
  if (status === 415) return "This request body is not supported by mikrokhoros Web.";
  if (status === 503) return "mikrokhoros Web is temporarily unavailable.";
  return "The action could not be completed. Refresh its context and try again.";
}

async function fetchWebCapability(path, body, signal) {
  const response = await window.fetch(path, {
    method: "POST",
    credentials: "same-origin",
    headers: { Accept: "application/json, application/octet-stream", "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal,
  });
  if (!response.ok) {
    const error = new Error(webErrorMessage(response.status));
    error.status = response.status;
    throw error;
  }
  const disposition = response.headers.get("Content-Disposition") || "";
  if (/attachment/i.test(disposition)) {
    return { download: await response.blob(), disposition };
  }
  return response.json();
}

function safeDownloadName(disposition) {
  const match = disposition.match(/filename\*?=(?:UTF-8''|\")?([^\";]+)/i);
  let decoded = "mikrokhoros-download";
  if (match) {
    try { decoded = decodeURIComponent(match[1].replace(/\"$/, "")); }
    catch { decoded = "mikrokhoros-download"; }
  }
  return decoded.replace(/[^a-zA-Z0-9._-]/g, "_").slice(0, 128) || "mikrokhoros-download";
}

function beginDownload(result) {
  const url = URL.createObjectURL(result.download);
  const anchor = node("a");
  anchor.href = url;
  anchor.download = safeDownloadName(result.disposition);
  anchor.hidden = true;
  document.body.append(anchor);
  anchor.click();
  anchor.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 0);
}

async function submitWebOperation(event, descriptor) {
  event.preventDefault();
  const form = event.currentTarget;
  const status = form.querySelector(".inline-status");
  const primary = form.querySelector(".action-button");
  delete status.dataset.testid;
  status.classList.remove("is-error");
  try {
    const payload = collectWebPayload(form, descriptor);
    if (descriptor.mode === "privateViewer" && !state.privateRevealed) {
      state.privateRevealed = true;
      primary.textContent = "Reveal again";
    }
    if (descriptor.mode === "reportStream") {
      await startReportStream(form, descriptor, payload, status);
      return;
    }
    primary.disabled = true;
    status.textContent = descriptor.mode === "confirmation" ? "Preparing consequences…" : "Running action…";
    state.webRequest?.abort();
    const controller = new AbortController();
    state.webRequest = controller;
    let path = "/api/v1/web/execute";
    let body = { operationID: payload.operationID, ...(payload.worldID ? { worldID: payload.worldID } : {}), fields: payload.fields };
    if (descriptor.mode === "confirmation") path = "/api/v1/web/prepare";
    if (descriptor.mode === "secret") {
      path = "/api/v1/web/secret";
      body = { ...body, secret: payload.secret || "" };
    }
    if (descriptor.mode === "agentController") path = "/api/v1/web/agent-controller";
    const result = await fetchWebCapability(path, body, controller.signal);
    state.webRequest = null;
    if (descriptor.mode === "confirmation") renderPreparedConfirmation(form, descriptor, result, status);
    else if (result.download) {
      beginDownload(result);
      status.textContent = "Download started.";
    } else {
      renderWebResult(descriptor, result, { secret: descriptor.mode === "secret" ? payload.secret : "" });
      if (result.accepted === false && descriptor.failureTestID) status.dataset.testid = descriptor.failureTestID;
      status.textContent = result.accepted === false ? "Action was not accepted." : "Action completed.";
      if (descriptor.mode === "agentController") appendControllerTranscript(result);
      await refreshWebTargets(descriptor, result);
    }
  } catch (error) {
    if (error?.name === "AbortError") return;
    status.textContent = error?.message || webErrorMessage(0);
    status.classList.add("is-error");
    if (descriptor.failureTestID) status.dataset.testid = descriptor.failureTestID;
  } finally {
    state.webRequest = null;
    primary.disabled = false;
    if (descriptor.mode === "secret") clearSensitiveFields();
  }
}

function appendControllerTranscript(result) {
  const entry = [result?.displayCommand, result?.standardOutput, result?.standardError].filter((value) => typeof value === "string" && value).join("\n");
  if (entry) state.controllerTranscript.push(entry.slice(0, 12_000));
  state.controllerTranscript = state.controllerTranscript.slice(-24);
  const transcript = elements.operationDetail.querySelector(".controller-transcript");
  if (transcript) transcript.textContent = state.controllerTranscript.length ? state.controllerTranscript.join("\n\n") : "No actions submitted.";
}

async function startReportStream(form, descriptor, payload, status) {
  if (state.streamController) return;
  const start = form.querySelector(".action-button");
  const stop = form.querySelector("[data-stop-stream]");
  const controller = new AbortController();
  state.streamController = controller;
  start.disabled = true;
  stop.disabled = false;
  status.textContent = "Following reports…";
  elements.operationDetail.querySelector(".result-viewer")?.remove();
  const viewer = node("section", "result-viewer");
  viewer.append(node("h3", "", "Report stream"));
  const output = node("pre", "result-code", "Waiting for reports…");
  viewer.append(output);
  elements.operationDetail.append(viewer);
  try {
    const response = await window.fetch("/api/v1/web/report-follow", {
      method: "POST",
      credentials: "same-origin",
      headers: { Accept: "text/plain", "Content-Type": "application/json" },
      body: JSON.stringify({ operationID: payload.operationID, ...(payload.worldID ? { worldID: payload.worldID } : {}), fields: payload.fields }),
      signal: controller.signal,
    });
    if (!response.ok) throw new Error(webErrorMessage(response.status));
    const reader = response.body?.getReader();
    if (!reader) throw new Error("Streaming is not supported by this response.");
    const decoder = new TextDecoder();
    let text = "";
    while (true) {
      const chunk = await reader.read();
      if (chunk.done) break;
      text = `${text}${decoder.decode(chunk.value, { stream: true })}`.slice(-120_000);
      output.textContent = text || "Waiting for reports…";
    }
    status.textContent = "Report stream ended.";
  } catch (error) {
    if (error?.name === "AbortError") status.textContent = "Report stream stopped.";
    else {
      status.textContent = error?.message || webErrorMessage(0);
      status.classList.add("is-error");
    }
  } finally {
    state.streamController = null;
    start.disabled = false;
    stop.disabled = true;
  }
}

function stopReportStream(form, status) {
  if (!state.streamController) return;
  state.streamController.abort();
  form.querySelector("[data-stop-stream]").disabled = true;
  status.textContent = "Stopping report stream…";
}

function openHelp({ focusSearch = true, query = "" } = {}) {
  closeActiveSurface({ restoreFocus: false });
  state.helpReturnFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null;
  elements.helpBackdrop.hidden = false;
  elements.helpSearch.value = String(query || "").slice(0, 512);
  renderHelpResults();
  (focusSearch ? elements.helpSearch : elements.helpDialog).focus();
}

function closeHelp({ restoreFocus = true } = {}) {
  if (elements.helpBackdrop.hidden) return;
  elements.helpBackdrop.hidden = true;
  elements.helpSearch.value = "";
  const returnFocus = state.helpReturnFocus;
  state.helpReturnFocus = null;
  if (restoreFocus && returnFocus?.isConnected) returnFocus.focus({ preventScroll: true });
}

function setupBaseInteractions() {
  wireSurface(elements.appViewTrigger, elements.appViewMenu);
  wireSurface(elements.worldTrigger, elements.worldMenu);
  wireSurface(elements.agentChoiceTrigger, elements.agentChoiceMenu);
  wireSurface(elements.notificationTrigger, elements.notificationPopover, { focusFirst: false });
  wireSurface(elements.viewTrigger, elements.viewMenu);
  elements.cellQuickMenu.addEventListener("keydown", menuKeyboard);
  elements.worldCreateForm.addEventListener("submit", submitWorldCreation);
  elements.worldCreateCancel.addEventListener("click", () => closeWorldCreateDialog());
  elements.worldCreateBackdrop.addEventListener("pointerdown", (event) => {
    if (event.target === elements.worldCreateBackdrop) closeWorldCreateDialog();
  });
  elements.addAgentButton.addEventListener("click", openAgentAddDialog);
  elements.agentAddForm.addEventListener("submit", submitAgentAddition);
  elements.agentAddCancel.addEventListener("click", () => closeAgentAddDialog());
  elements.agentAddBackdrop.addEventListener("pointerdown", (event) => {
    if (event.target === elements.agentAddBackdrop) closeAgentAddDialog();
  });
  elements.agentAutoAdapt.addEventListener("click", () => {
    if (elements.agentAutoAdapt.disabled) return;
    state.agentAddAutoAdapt = !state.agentAddAutoAdapt;
    elements.agentAutoAdapt.setAttribute(
      "aria-pressed",
      state.agentAddAutoAdapt ? "true" : "false",
    );
    elements.agentAutoAdapt.querySelector("img").hidden = !state.agentAddAutoAdapt;
  });
  elements.allAgentsTrigger.addEventListener("click", () => {
    const worldID = state.snapshot?.selectedWorldID;
    if (!isExactID(worldID)) return;
    if (state.expandedAgentWorlds.has(worldID)) state.expandedAgentWorlds.delete(worldID);
    else state.expandedAgentWorlds.add(worldID);
    renderAgents(state.snapshot);
    elements.allAgentsTrigger.focus({ preventScroll: true });
  });

  elements.notificationTrigger.addEventListener("click", () => {
    if (!elements.notificationPopover.hidden) markLatestReportSeen();
  });

  const consoleTabs = [
    elements.consoleOutputTab,
    elements.consoleAgentTab,
    elements.consoleObjectTab,
  ];
  for (const tab of consoleTabs) {
    tab.addEventListener("click", () => selectConsoleTab(tab.dataset.consoleTab));
    tab.addEventListener("keydown", (event) => {
      const current = consoleTabs.indexOf(tab);
      let next = null;
      if (event.key === "ArrowRight") next = consoleTabs[(current + 1) % consoleTabs.length];
      if (event.key === "ArrowLeft") next = consoleTabs[(current - 1 + consoleTabs.length) % consoleTabs.length];
      if (event.key === "Home") next = consoleTabs[0];
      if (event.key === "End") next = consoleTabs[consoleTabs.length - 1];
      if (!next) return;
      event.preventDefault();
      selectConsoleTab(next.dataset.consoleTab, { focus: true });
    });
  }
  elements.consoleAgentContextMode.addEventListener("click", toggleConsoleContextFreeze);
  elements.consoleObjectContextMode.addEventListener("click", toggleConsoleContextFreeze);

  elements.consoleMinimize.addEventListener("click", () => {
    setConsoleMinimized(!state.consoleMinimized);
    if (state.consoleMinimized) closeCommandSuggestions();
  });
  elements.worldCommandForm.addEventListener("submit", submitWorldCommand);
  elements.worldCommandInput.addEventListener("input", () => {
    renderCommandHighlight();
    scheduleCommandCompletions();
  });
  elements.worldCommandInput.addEventListener("scroll", renderCommandHighlight);
  elements.worldCommandInput.addEventListener("focus", scheduleCommandCompletions);
  elements.worldCommandInput.addEventListener("keydown", (event) => {
    if (event.key === "ArrowDown" && state.consoleSuggestions.length) {
      event.preventDefault();
      setCommandSuggestionIndex(state.consoleSuggestionIndex + 1);
      return;
    }
    if (event.key === "ArrowUp" && state.consoleSuggestions.length) {
      event.preventDefault();
      setCommandSuggestionIndex(state.consoleSuggestionIndex - 1);
      return;
    }
    if (event.key === "Tab" && state.consoleSuggestions.length) {
      event.preventDefault();
      acceptCommandSuggestion();
      return;
    }
    if (event.key === "Escape" && !elements.commandSuggestions.hidden) {
      event.preventDefault();
      event.stopPropagation();
      closeCommandSuggestions();
    }
  });

  elements.consoleResizeHandle.addEventListener("pointerdown", (event) => {
    if (event.button !== 0 || state.consoleMinimized) return;
    event.preventDefault();
    state.consoleResizeGesture = {
      id: event.pointerId,
      originY: event.clientY,
      originHeight: state.consoleHeight,
    };
    try {
      elements.consoleResizeHandle.setPointerCapture(event.pointerId);
    } catch {
      state.consoleResizeGesture = null;
    }
  });
  elements.consoleResizeHandle.addEventListener("pointermove", (event) => {
    const gesture = state.consoleResizeGesture;
    if (!gesture || gesture.id !== event.pointerId) return;
    event.preventDefault();
    setConsoleHeight(gesture.originHeight + gesture.originY - event.clientY);
  });
  const finishConsoleResize = (event) => {
    const gesture = state.consoleResizeGesture;
    if (!gesture || gesture.id !== event.pointerId) return;
    state.consoleResizeGesture = null;
    try {
      elements.consoleResizeHandle.releasePointerCapture(event.pointerId);
    } catch {
      // The browser may already have released pointer capture.
    }
  };
  elements.consoleResizeHandle.addEventListener("pointerup", finishConsoleResize);
  elements.consoleResizeHandle.addEventListener("pointercancel", finishConsoleResize);
  elements.consoleResizeHandle.addEventListener("lostpointercapture", (event) => {
    if (state.consoleResizeGesture?.id === event.pointerId) state.consoleResizeGesture = null;
  });
  elements.consoleResizeHandle.addEventListener("keydown", (event) => {
    let next = null;
    if (event.key === "ArrowUp") next = state.consoleHeight + 12;
    if (event.key === "ArrowDown") next = state.consoleHeight - 12;
    if (event.key === "Home") next = CONSOLE_MIN_HEIGHT;
    if (event.key === "End") next = consoleMaximumHeight();
    if (next === null) return;
    event.preventDefault();
    setConsoleHeight(next);
  });

  elements.sidebarResizeHandle.addEventListener("pointerdown", (event) => {
    if (event.button !== 0 || !sidebarResizeEnabled()) return;
    event.preventDefault();
    event.stopPropagation();
    closeActiveSurface({ restoreFocus: false });
    state.sidebarResizeGesture = {
      id: event.pointerId,
      originX: event.clientX,
      originWidth: effectiveSidebarWidth(),
      originPreferredWidth: state.sidebarPreferredWidth,
    };
    elements.appShell.classList.add("is-resizing-sidebar");
    document.body.classList.add("is-resizing-sidebar");
    try {
      elements.sidebarResizeHandle.setPointerCapture(event.pointerId);
    } catch {
      finishSidebarResize({ pointerID: event.pointerId });
    }
  });
  elements.sidebarResizeHandle.addEventListener("pointermove", (event) => {
    const gesture = state.sidebarResizeGesture;
    if (!gesture || gesture.id !== event.pointerId) return;
    event.preventDefault();
    setSidebarPreferredWidth(gesture.originWidth + event.clientX - gesture.originX);
  });
  elements.sidebarResizeHandle.addEventListener("pointerup", (event) => {
    finishSidebarResize({ pointerID: event.pointerId, commit: true, releaseCapture: true });
  });
  elements.sidebarResizeHandle.addEventListener("pointercancel", (event) => {
    finishSidebarResize({ pointerID: event.pointerId, commit: false, releaseCapture: false });
  });
  elements.sidebarResizeHandle.addEventListener("lostpointercapture", (event) => {
    finishSidebarResize({ pointerID: event.pointerId, commit: false, releaseCapture: false });
  });
  elements.sidebarResizeHandle.addEventListener("keydown", (event) => {
    if (!sidebarResizeEnabled()) return;
    let next = null;
    const step = event.shiftKey ? SIDEBAR_LARGE_KEYBOARD_STEP : SIDEBAR_KEYBOARD_STEP;
    if (event.key === "ArrowLeft") next = effectiveSidebarWidth() - step;
    if (event.key === "ArrowRight") next = effectiveSidebarWidth() + step;
    if (event.key === "Home") next = SIDEBAR_MIN_WIDTH;
    if (event.key === "End") next = sidebarMaximumWidth();
    if (event.key === "0") next = SIDEBAR_DEFAULT_WIDTH;
    if (next === null) return;
    event.preventDefault();
    setSidebarPreferredWidth(next, { persist: true });
  });
  window.addEventListener("blur", () => finishSidebarResize());
  window.addEventListener("keydown", (event) => {
    if (event.key !== "Escape" || !state.sidebarResizeGesture) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    finishSidebarResize();
  }, true);

  document.addEventListener("pointerdown", (event) => {
    if (
      !elements.commandSuggestions.hidden
      && !elements.worldCommandForm.contains(event.target)
      && !elements.commandSuggestions.contains(event.target)
    ) closeCommandSuggestions();
    if (
      state.webCombobox
      && !state.webCombobox.root.contains(event.target)
    ) closeWebCombobox();
    if (
      state.webAutocomplete
      && !state.webAutocomplete.root.contains(event.target)
    ) closeWebAutocomplete();
    if (!state.activeSurface) return;
    const { trigger, panel } = state.activeSurface;
    if (!panel.contains(event.target) && !trigger.contains(event.target)) {
      if (shouldConsumeEmptyCellDismissal(state.activeSurface, event.target)) {
        cancelPendingObjectActivation();
        state.consumeNextEmptyCellActivation = true;
        window.clearTimeout(state.emptyCellDismissalClearTimer);
      }
      closeActiveSurface({ restoreFocus: false });
    }
  });

  document.addEventListener("keydown", (event) => {
    if (!elements.helpBackdrop.hidden) {
      if (event.key === "Tab") trapModalFocus(event, elements.helpDialog);
      if (event.key === "Escape") {
        event.preventDefault();
        closeHelp();
      }
      return;
    }
    if (!elements.agentAddBackdrop.hidden) {
      if (event.key === "Escape" && state.activeSurface?.panel === elements.agentChoiceMenu) {
        event.preventDefault();
        closeActiveSurface();
        return;
      }
      if (event.key === "Tab") trapModalFocus(event, elements.agentAddDialog);
      if (event.key === "Escape") {
        event.preventDefault();
        closeAgentAddDialog();
      }
      return;
    }
    if (!elements.worldCreateBackdrop.hidden) {
      if (event.key === "Tab") trapModalFocus(event, elements.worldCreateDialog);
      if (event.key === "Escape") {
        event.preventDefault();
        closeWorldCreateDialog();
      }
      return;
    }
    if (!elements.inspectorBackdrop.hidden && event.key === "Tab") {
      trapModalFocus(event, elements.objectInspector);
      return;
    }
    const shortcutTarget = event.target;
    const shortcutIsEditing = shortcutTarget instanceof HTMLElement
      && (
        shortcutTarget.isContentEditable
        || shortcutTarget.matches("input, textarea, select")
      );
    const shortcutKey = event.key.toLowerCase();
    const shortcutTabs = { "1": "output", "2": "agent", "3": "object" };
    if (
      !event.defaultPrevented
      && !event.repeat
      && !event.isComposing
      && !event.altKey
      && !event.ctrlKey
      && !event.metaKey
      && !shortcutIsEditing
      && !state.activeSurface
      && elements.inspectorBackdrop.hidden
    ) {
      if (event.key === "/") {
        event.preventDefault();
        openHelp();
        return;
      }
      const consoleTab = shortcutTabs[shortcutKey];
      if (consoleTab && state.webView === "world") {
        event.preventDefault();
        if (state.consoleMinimized) setConsoleMinimized(false);
        selectConsoleTab(consoleTab);
        announce(`${formatKey(consoleTab)} information selected.`);
        return;
      }
      if (
        shortcutKey === "c"
        && state.webView === "world"
        && !state.consoleMinimized
        && (state.consoleTab === "agent" || state.consoleTab === "object")
      ) {
        event.preventDefault();
        toggleConsoleContextFreeze();
        return;
      }
    }
    if (event.key === "Escape") {
      if (!elements.inspectorBackdrop.hidden) closeInspector();
      else closeActiveSurface();
    }
  });

  for (const row of elements.appViewMenu.querySelectorAll("[data-app-view]")) {
    row.addEventListener("click", () => {
      const view = row.dataset.appView;
      closeActiveSurface({ restoreFocus: false });
      switchWebView(view);
      elements.appViewTrigger.focus();
    });
  }

  for (const row of elements.viewMenu.querySelectorAll("[data-view-action]")) {
    row.addEventListener("click", () => {
      const action = row.dataset.viewAction;
      closeActiveSurface({ restoreFocus: false });
      applyViewAction(action);
      elements.viewTrigger.focus();
    });
  }

  elements.sidebarToggle.addEventListener("click", () => {
    finishSidebarResize();
    const collapsed = elements.appShell.dataset.sidebar !== "collapsed";
    setSidebarCollapsed(collapsed);
    window.setTimeout(renderWorld, 230);
  });

  window.matchMedia("(max-width: 760px)").addEventListener("change", (event) => {
    if (event.matches) setSidebarCollapsed(true);
  });

  elements.inventoryShortcut.addEventListener("click", () => {
    switchWebView("inventory");
  });
  elements.settingsButton.addEventListener("click", () => {
    switchWebView("settings");
  });
  elements.helpButton.addEventListener("click", () => openHelp());
  elements.helpClose.addEventListener("click", () => closeHelp());
  elements.helpBackdrop.addEventListener("pointerdown", (event) => {
    if (event.target === elements.helpBackdrop) closeHelp();
  });
  elements.helpSearch.addEventListener("input", renderHelpResults);

  elements.humanViewButton.addEventListener("click", () => {
    restoreHumanViewForWorld(state.snapshot?.selectedWorldID, {
      returnFocus: elements.humanViewButton,
    });
  });

  elements.containerBack.addEventListener("click", async () => {
    const world = state.snapshot?.selectedWorldID;
    const parent = state.snapshot?.container?.parentContainerID;
    if (!isExactID(world)) return;
    leaveFollowForManualNavigation();
    const route = isExactID(parent) && parent !== world ? { world, container: parent } : { world };
    updateRoute(route);
    const opened = await loadWorld({ route, mode: "reset-human" });
    if (opened) saveHumanView();
  });

  elements.inspectorClose.addEventListener("click", closeInspector);
  elements.inspectorBackdrop.addEventListener("pointerdown", (event) => {
    if (event.target === elements.inspectorBackdrop) closeInspector();
  });
  elements.pinObjectButton.addEventListener("click", toggleSelectedPin);
  elements.openContainerButton.addEventListener("click", openSelectedContainer);

  window.addEventListener("popstate", () => {
    const route = currentRoute();
    if (route.view !== "world") {
      switchWebView(route.view, { historyMode: null });
      return;
    }
    if (state.webView !== "world") switchWebView("world", { historyMode: null });
    stopFollowPolling();
    state.following = false;
    state.followedAgentID = null;
    const humanRoute = { world: route.world, container: route.container };
    if (route.focus) updateRoute(humanRoute, "replace");
    loadWorld({ route: humanRoute, mode: "reset-human" });
  });
  document.addEventListener("visibilitychange", () => {
    if (!state.following) return;
    if (document.hidden) window.clearTimeout(state.followTimer);
    else scheduleFollowPoll(state.followGeneration, 0);
  });
  setupWorldInput();
}

function setupWorldInput() {
  elements.worldViewport.addEventListener(
    "click",
    (event) => {
      if (state.consumeNextEmptyCellActivation) {
        const targetsEmptyCell = event.target instanceof Element
          && Boolean(event.target.closest(".world-cell.is-empty"));
        state.consumeNextEmptyCellActivation = false;
        window.clearTimeout(state.emptyCellDismissalClearTimer);
        if (targetsEmptyCell) {
          event.preventDefault();
          event.stopImmediatePropagation();
          return;
        }
      }
      if (!state.suppressNextMapClick) return;
      state.suppressNextMapClick = false;
      window.clearTimeout(state.suppressClearTimer);
      event.preventDefault();
      event.stopImmediatePropagation();
    },
    true,
  );

  elements.worldViewport.addEventListener("pointerdown", (event) => {
    if (
      event.button !== 0
      || state.pointerGesture
      || event.target.closest("#cellQuickMenu")
    ) return;
    state.consumeNextEmptyCellActivation = false;
    window.clearTimeout(state.emptyCellDismissalClearTimer);
    state.suppressNextMapClick = false;
    window.clearTimeout(state.suppressClearTimer);
    state.pointerGesture = {
      id: event.pointerId,
      originX: event.clientX,
      originY: event.clientY,
      lastX: event.clientX,
      lastY: event.clientY,
      dragging: false,
      captured: false,
    };
  });

  elements.worldViewport.addEventListener("pointermove", (event) => {
    const gesture = state.pointerGesture;
    if (gesture && gesture.id === event.pointerId) {
      const distance = Math.hypot(
        event.clientX - gesture.originX,
        event.clientY - gesture.originY,
      );
      if (!gesture.dragging && distance >= DRAG_THRESHOLD_PX) {
        gesture.dragging = true;
        setConsoleHover(null);
        state.consumeNextEmptyCellActivation = false;
        window.clearTimeout(state.emptyCellDismissalClearTimer);
        cancelPendingObjectActivation();
        closeActiveSurface({ restoreFocus: false });
        leaveFollowForManualNavigation();
        try {
          elements.worldViewport.setPointerCapture(event.pointerId);
          gesture.captured = true;
        } catch {
          gesture.captured = false;
        }
        elements.worldViewport.classList.add("is-panning");
      }
      if (!gesture.dragging) return;
      event.preventDefault();
      const baseCell = Number.parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--cell-size"));
      const cell = baseCell * state.zoom;
      state.cameraX -= (event.clientX - gesture.lastX) / cell;
      state.cameraY -= (event.clientY - gesture.lastY) / cell;
      gesture.lastX = event.clientX;
      gesture.lastY = event.clientY;
      renderWorld();
      return;
    }
  });

  function finishGesture(event, { cancelled = false } = {}) {
    const gesture = state.pointerGesture;
    if (!gesture || gesture.id !== event.pointerId) return;
    state.pointerGesture = null;
    elements.worldViewport.classList.remove("is-panning");
    if (gesture.captured) {
      try {
        elements.worldViewport.releasePointerCapture(event.pointerId);
      } catch {
        // The browser may already have released the pointer capture.
      }
    }
    if (gesture.dragging && !cancelled) {
      state.suppressNextMapClick = true;
      window.clearTimeout(state.suppressClearTimer);
      state.suppressClearTimer = window.setTimeout(() => {
        state.suppressNextMapClick = false;
      }, 0);
      saveHumanView();
      announce("My view moved.");
    } else if (cancelled) {
      state.consumeNextEmptyCellActivation = false;
      window.clearTimeout(state.emptyCellDismissalClearTimer);
    } else if (state.consumeNextEmptyCellActivation) {
      window.clearTimeout(state.emptyCellDismissalClearTimer);
      state.emptyCellDismissalClearTimer = window.setTimeout(() => {
        state.consumeNextEmptyCellActivation = false;
      }, 0);
    }
  }
  elements.worldViewport.addEventListener("pointerup", (event) => finishGesture(event));
  elements.worldViewport.addEventListener("pointercancel", (event) => {
    finishGesture(event, { cancelled: true });
  });
  elements.worldViewport.addEventListener("lostpointercapture", (event) => {
    const gesture = state.pointerGesture;
    if (!gesture || gesture.id !== event.pointerId) return;
    if (gesture.dragging) saveHumanView();
    state.pointerGesture = null;
    state.consumeNextEmptyCellActivation = false;
    window.clearTimeout(state.emptyCellDismissalClearTimer);
    state.suppressNextMapClick = false;
    elements.worldViewport.classList.remove("is-panning");
  });
  elements.worldViewport.addEventListener(
    "wheel",
    (event) => {
      event.preventDefault();
      leaveFollowForManualNavigation();
      setZoom(state.zoom + (event.deltaY < 0 ? 0.1 : -0.1), { manual: false });
      saveHumanView();
    },
    { passive: false },
  );

  elements.worldViewport.addEventListener("keydown", (event) => {
    const movements = {
      ArrowLeft: [-1, 0],
      ArrowRight: [1, 0],
      ArrowUp: [0, -1],
      ArrowDown: [0, 1],
    };
    if (movements[event.key]) {
      event.preventDefault();
      leaveFollowForManualNavigation();
      state.keyboardCell.x += movements[event.key][0];
      state.keyboardCell.y += movements[event.key][1];
      state.cameraX = state.keyboardCell.x;
      state.cameraY = state.keyboardCell.y;
      renderWorld();
      setConsoleHover(state.keyboardCell);
      saveHumanView();
      return;
    }
    if (event.key === "+" || event.key === "=") {
      event.preventDefault();
      setZoom(state.zoom + 0.15);
    }
    if (event.key === "-") {
      event.preventDefault();
      setZoom(state.zoom - 0.15);
    }
    if (event.key === "0") {
      event.preventDefault();
      void restoreHumanViewForWorld(state.snapshot?.selectedWorldID, { historyMode: "replace" });
    }
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      const coordinate = state.keyboardCell;
      setConsoleHover(coordinate);
      const occupants = occupantsAt(coordinate);
      const trigger = Array.from(elements.entityLayer.querySelectorAll(".world-cell")).find(
        (cell) => cell.dataset.x === String(coordinate.x) && cell.dataset.y === String(coordinate.y),
      );
      if (trigger) openCellQuickMenu(coordinate, occupants, trigger);
    }
  });

  const observer = new ResizeObserver(() => {
    setConsoleHeight(state.consoleHeight);
    updateSidebarResizeHandle();
    renderWorld();
  });
  observer.observe(elements.worldViewport);
  const sidebarObserver = new ResizeObserver(updateSidebarResizeHandle);
  sidebarObserver.observe(elements.appShell);
}

async function start() {
  installGlassSurfaces();
  restoreSidebarWidth();
  if (isCompactSidebarViewport()) setSidebarCollapsed(true);
  setConsoleHeight(CONSOLE_DEFAULT_HEIGHT);
  setConsoleMinimized(false);
  selectConsoleTab("output");
  renderCommandHighlight();
  renderConsoleContext();
  setWorldCommandAvailability(false);
  setupInteractions();
  try {
    await establishSession();
    const initial = currentRoute();
    const capabilitiesPromise = loadCapabilities({ preserveSelection: false });
    const humanRoute = { world: initial.world, container: initial.container };
    if (initial.focus && initial.view === "world") updateRoute(humanRoute, "replace");
    if (isExactID(initial.world) && storedHumanView(initial.world)) {
      await restoreHumanViewForWorld(initial.world, { historyMode: "replace" });
    } else {
      const opened = await loadWorld({ route: humanRoute, mode: "reset-human" });
      const selectedWorldID = state.snapshot?.selectedWorldID;
      if (opened && !initial.container && storedHumanView(selectedWorldID)) {
        await restoreHumanViewForWorld(selectedWorldID, { historyMode: "replace" });
      }
    }
    await capabilitiesPromise;
    rememberWorldRoute();
    if (initial.view === "world") {
      switchWebView("world", { historyMode: null });
    } else {
      updateRoute(initial, "replace");
      switchWebView(initial.view, { historyMode: null });
    }
  } catch {
    renderUnavailable("Restart khoros web and open the complete launch link printed by the command.");
  }
}

start();

/*
 * mikrokhoros Web projections
 *
 * The World is intentionally the only spatial surface. These projections make
 * the desktop product legible as a set of human domains; capabilities remain a
 * bounded transport behind named controls and the Help reference.
 */

const DOMAIN_ENDPOINTS = Object.freeze({
  agentManager: "/api/v1/agents",
  inventory: "/api/v1/inventory",
  packages: "/api/v1/packages",
  templates: "/api/v1/templates",
  settings: "/api/v1/settings",
});

const NATIVE_ACTION_LABELS = Object.freeze({
  agentCreate: "New agent",
  agentAdd: "Place in World",
  agentRemove: "Remove from World",
  agentConfigure: "Configure agent",
  agentProfileSet: "Edit profile",
  agentProfileClear: "Clear profile",
  agentRetry: "Retry unread notification",
  agentShell: "Open action session",
  inventoryCreate: "New source",
  inventoryConfigure: "Configure source",
  inventorySecretSet: "Set credential",
  inventorySecretClear: "Clear credential",
  inventoryCapabilityList: "Review capabilities",
  inventoryCapabilityGrant: "Grant capability",
  inventoryCapabilityRevoke: "Revoke capability",
  inventoryFork: "Fork for World",
  inventoryDeploy: "Deploy to World",
  inventoryCopiesList: "World copies",
  inventoryListenList: "Listeners",
  inventoryReportsList: "Reports",
  inventoryReportsFollow: "Follow reports",
  inventoryRestockList: "Restocking",
  inventoryRestockCreate: "New restock rule",
  inventoryPackageRemove: "Remove package",
  inventoryInstall: "Install package",
  inventoryFolderCreate: "New folder",
  inventoryFolderRename: "Rename folder",
  inventoryFolderMove: "Move folder",
  inventoryFolderDelete: "Delete folder",
  inventoryMove: "Move source",
  inventoryDelete: "Remove source",
  inventoryActionRun: "Run object action",
  inventoryViewShow: "Open object view",
  worldObjectActionRun: "Run object action",
  worldObjectViewShow: "Open object view",
  worldObjectMove: "Move object",
  worldTemplateStatus: "Check status in World",
  worldTemplateApply: "Apply to World",
  worldCreate: "Create World",
  initialize: "Initialize product",
  status: "Product status",
  configShow: "Configuration summary",
  configKeys: "Configuration keys",
  configGet: "Read setting",
  configPath: "Configuration selection",
  configSet: "Edit setting",
  configReset: "Reset setting",
  configValidate: "Validate settings",
  adapters: "AI adapters",
  web: "Local host",
  doctor: "Run diagnostics",
});

const NATIVE_ACTION_CANDIDATES = Object.freeze({
  newAgent: ["agentCreate"],
  configureAgent: ["agentConfigure"],
  profileAgent: ["agentProfileSet"],
  clearAgentProfile: ["agentProfileClear"],
  retryAgent: ["agentRetry"],
  agentSession: ["agentShell"],
  removeAgent: ["agentRemove"],
  newSource: ["inventoryCreate"],
  configureSource: ["inventoryConfigure"],
  credentialSource: ["inventorySecretSet"],
  clearCredentialSource: ["inventorySecretClear"],
  listCapabilities: ["inventoryCapabilityList"],
  grantCapability: ["inventoryCapabilityGrant"],
  revokeCapability: ["inventoryCapabilityRevoke"],
  forkSource: ["inventoryFork"],
  deploySource: ["inventoryDeploy"],
  copiesSource: ["inventoryCopiesList"],
  listenersSource: ["inventoryListenList"],
  reportsSource: ["inventoryReportsList"],
  followReportsSource: ["inventoryReportsFollow"],
  restockSource: ["inventoryRestockList"],
  createRestockSource: ["inventoryRestockCreate"],
  moveSource: ["inventoryMove"],
  removeSource: ["inventoryDelete"],
  objectAction: ["inventoryActionRun"],
  objectView: ["inventoryViewShow"],
  worldObjectAction: ["worldObjectActionRun"],
  worldObjectView: ["worldObjectViewShow"],
  worldObjectMove: ["worldObjectMove"],
  newFolder: ["inventoryFolderCreate"],
  renameFolder: ["inventoryFolderRename"],
  moveFolder: ["inventoryFolderMove"],
  deleteFolder: ["inventoryFolderDelete"],
  installPackage: ["inventoryInstall"],
  removePackage: ["inventoryPackageRemove"],
  templateStatus: ["worldTemplateStatus"],
  templateApply: ["worldTemplateApply"],
  createWorld: ["worldCreate"],
  initializeProduct: ["initialize"],
  productStatus: ["status"],
  showConfiguration: ["configShow"],
  configurationKeys: ["configKeys"],
  readSetting: ["configGet"],
  configurationSelection: ["configPath"],
  editSetting: ["configSet"],
  resetSetting: ["configReset"],
  validateSettings: ["configValidate"],
  adapters: ["adapters"],
  hostStatus: ["web"],
  diagnostics: ["doctor"],
});

// WebAssetStore deliberately serves a small vetted Phosphor subset. Native
// surfaces use semantic aliases rather than requesting an asset outside it.
const WEB_ICON_ALIAS = Object.freeze({
  "folder": "archive",
  "folder-plus": "plus",
  "pulse": "circle-notch",
  "users": "user-plus",
  "terminal-window": "arrow-square-out",
  "sparkle": "circle-notch",
  "warning-circle": "info",
  "key": "shield",
  "sliders-horizontal": "dots-three",
  "identification-card": "user-plus",
  "arrow-right": "arrow-square-out",
  "play": "arrow-square-out",
  "check-circle": "check",
  "stethoscope": "info",
  "pencil-simple": "dots-three",
  "trash": "x",
});

function icon(path, className = "menu-icon", alt = "") {
  const image = document.createElement("img");
  image.className = className;
  image.src = `/icons/phosphor/${WEB_ICON_ALIAS[path] || path}.svg`;
  image.alt = alt;
  return image;
}

function nativeState() {
  if (!state.domainSnapshots) state.domainSnapshots = new Map();
  if (!state.domainSelections) state.domainSelections = {};
  if (!state.domainStatus) state.domainStatus = { loading: false, error: null };
  if (!Object.prototype.hasOwnProperty.call(state, "domainRequest")) state.domainRequest = null;
  if (!Object.prototype.hasOwnProperty.call(state, "actionReturnFocus")) state.actionReturnFocus = null;
  if (!Object.prototype.hasOwnProperty.call(state, "activeActionLabel")) state.activeActionLabel = null;
  return state;
}

function boundedRouteValue(value) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed && trimmed.length <= 256 ? trimmed : null;
}

function currentRoute() {
  const parameters = new URLSearchParams(window.location.search);
  const world = parameters.get("world");
  const container = parameters.get("container");
  const focus = parameters.get("focus");
  return {
    view: ROUTABLE_WEB_VIEWS.includes(parameters.get("view")) ? parameters.get("view") : "world",
    world: isExactID(world) ? world : null,
    container: isExactID(container) ? container : null,
    focus: isExactID(focus) ? focus : null,
    agent: boundedRouteValue(parameters.get("agent")),
    source: boundedRouteValue(parameters.get("source")),
    folder: boundedRouteValue(parameters.get("folder")),
    package: boundedRouteValue(parameters.get("package")),
    version: boundedRouteValue(parameters.get("version")),
    template: boundedRouteValue(parameters.get("template")),
    setting: boundedRouteValue(parameters.get("setting")),
  };
}

function updateRoute(next, mode = "push") {
  const parameters = new URLSearchParams();
  if (ROUTABLE_WEB_VIEWS.includes(next.view) && next.view !== "world") parameters.set("view", next.view);
  if (isExactID(next.world)) parameters.set("world", next.world);
  if (isExactID(next.container)) parameters.set("container", next.container);
  if (isExactID(next.focus)) parameters.set("focus", next.focus);
  for (const key of ["agent", "source", "folder", "package", "version", "template", "setting"]) {
    const value = boundedRouteValue(next[key]);
    if (value) parameters.set(key, value);
  }
  const query = parameters.toString();
  const url = query ? `/?${query}` : "/";
  const method = mode === "replace" ? "replaceState" : "pushState";
  window.history[method]({}, "", url);
}

function setDomainRoute(selection, { mode = "push" } = {}) {
  const route = currentRoute();
  const next = { view: state.webView };
  Object.assign(next, route, selection);
  for (const key of ["agent", "source", "folder", "package", "version", "template", "setting"]) {
    if (!(key in selection) && !(key in route)) next[key] = null;
  }
  updateRoute(next, mode);
}

function domainSelectionFromRoute(view, snapshot) {
  const route = currentRoute();
  const known = state.domainSelections?.[view] || {};
  if (view === "agentManager") {
    const agents = Array.isArray(snapshot?.agents) ? snapshot.agents : [];
    const id = route.agent || known.agent || agents[0]?.id || null;
    return { agent: agents.some((agent) => agent.id === id) ? id : agents[0]?.id || null };
  }
  if (view === "inventory") {
    const sources = Array.isArray(snapshot?.sources) ? snapshot.sources : [];
    const folders = Array.isArray(snapshot?.folders) ? snapshot.folders : [];
    const source = route.source || known.source;
    const folder = route.folder || known.folder;
    if (sources.some((item) => item.id === source)) return { source, folder: null };
    if (folders.some((item) => item.id === folder)) return { source: null, folder };
    return sources.length ? { source: sources[0].id, folder: null } : { source: null, folder: folders[0]?.id || null };
  }
  if (view === "packages") {
    const all = [...(Array.isArray(snapshot?.packages) ? snapshot.packages : []), ...(Array.isArray(snapshot?.retainedPackages) ? snapshot.retainedPackages : [])];
    const key = route.package && route.version ? `${route.package}@${route.version}` : known.packageKey;
    const selected = all.find((item) => `${item.id}@${item.version}` === key) || all[0] || null;
    return { packageKey: selected ? `${selected.id}@${selected.version}` : null };
  }
  if (view === "templates") {
    const templates = Array.isArray(snapshot?.templates) ? snapshot.templates : [];
    const key = route.template || known.templateKey;
    const selected = templates.find((item) => `${item.id}@${item.version}` === key || item.id === key) || templates[0] || null;
    return { templateKey: selected ? `${selected.id}@${selected.version}` : null };
  }
  if (view === "settings") {
    const groups = settingsSections(snapshot);
    const id = route.setting || known.setting || groups[0]?.id || null;
    return { setting: groups.some((group) => group.id === id) ? id : groups[0]?.id || null };
  }
  return {};
}

function domainSnapshotFor(view = state.webView) {
  return nativeState().domainSnapshots.get(view) || null;
}

function workspaceDetailScrollKey(view = state.webView) {
  const selection = nativeState().domainSelections[view] || {};
  if (view === "agentManager") return selection.agent || "none";
  if (view === "inventory") return selection.source ? `source:${selection.source}` : `folder:${selection.folder || "root"}`;
  if (view === "packages") return selection.packageKey || "none";
  if (view === "templates") return selection.templateKey || "none";
  if (view === "settings") return selection.setting || "none";
  return "root";
}

function workspaceScrollKey(view = state.webView) {
  return `${view}:${workspaceDetailScrollKey(view)}`;
}

function rememberWorkspaceScroll(view = state.webView, key = state.activeWorkspaceScrollKey) {
  if (view === "world" || !key || !elements.workspaceScrollRegion) return;
  state.workspaceScrollPositions.set(
    key,
    Math.max(0, elements.workspaceScrollRegion.scrollTop),
  );
  state.domainSidebarScrollPositions.set(
    view,
    Math.max(0, elements.domainSidebarContent.scrollTop),
  );
}

function restoreWorkspaceScroll(view = state.webView, key = workspaceScrollKey(view)) {
  if (view === "world") return;
  const workspacePosition = state.workspaceScrollPositions.get(key) || 0;
  const sidebarPosition = state.domainSidebarScrollPositions.get(view) || 0;
  window.requestAnimationFrame(() => {
    if (state.webView !== view || state.activeWorkspaceScrollKey !== key) return;
    elements.workspaceScrollRegion.scrollTop = workspacePosition;
    elements.domainSidebarContent.scrollTop = sidebarPosition;
  });
}

function normalizedDomainSnapshot(view, value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("mikrokhoros Web returned an invalid view.");
  const arrays = {
    agentManager: ["agents"],
    inventory: ["folders", "sources"],
    packages: ["packages", "retainedPackages"],
    templates: ["templates"],
    settings: ["groups", "adapters"],
  };
  for (const key of arrays[view] || []) {
    if (!Array.isArray(value[key])) throw new Error("mikrokhoros Web returned an incomplete view.");
  }
  return value;
}

async function loadDomainSnapshot(view = state.webView, { quiet = false } = {}) {
  if (!DOMAIN_ENDPOINTS[view]) return null;
  const runtime = nativeState();
  runtime.domainRequest?.abort();
  const controller = new AbortController();
  runtime.domainRequest = controller;
  runtime.domainStatus = { loading: true, error: null };
  if (state.webView === view) renderDomainView();
  try {
    const response = await window.fetch(DOMAIN_ENDPOINTS[view], {
      method: "GET",
      credentials: "same-origin",
      headers: { Accept: "application/json" },
      signal: controller.signal,
    });
    if (!response.ok) throw new Error(response.status === 401 || response.status === 403
      ? "Reopen the local app from its launch link."
      : "This local view is temporarily unavailable.");
    const snapshot = normalizedDomainSnapshot(view, await response.json());
    if (runtime.domainRequest !== controller) return null;
    runtime.domainSnapshots.set(view, snapshot);
    runtime.domainSelections[view] = domainSelectionFromRoute(view, snapshot);
    runtime.domainStatus = { loading: false, error: null };
    if (state.webView === view) {
      renderDomainView();
      if (!quiet) announce(`${WEB_VIEW_META[view].label} refreshed.`);
    }
    return snapshot;
  } catch (error) {
    if (error?.name === "AbortError") return null;
    if (runtime.domainRequest === controller) {
      runtime.domainStatus = { loading: false, error: error?.message || "This local view is temporarily unavailable." };
      if (state.webView === view) renderDomainView();
    }
    return null;
  } finally {
    if (runtime.domainRequest === controller) runtime.domainRequest = null;
  }
}

function clearNode(target) {
  target?.replaceChildren();
  return target;
}

function domainIconMark(visual, className = "domain-identity-symbol") {
  const mark = node("span", className);
  applySymbol(mark, visual || { shapeIndex: 0, colorIndex: 0 });
  mark.setAttribute("aria-hidden", "true");
  return mark;
}

function compactDate(value) {
  if (typeof value !== "string") return "";
  const date = new Date(value);
  if (!Number.isFinite(date.valueOf())) return "";
  return new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", year: "numeric" }).format(date);
}

function domainButton(label, iconName, onClick, { selected = false, muted = false, title = "" } = {}) {
  const button = node("button", "domain-entity-row");
  button.type = "button";
  button.classList.toggle("is-selected", selected);
  if (selected) button.setAttribute("aria-current", "page");
  button.classList.toggle("is-muted", muted);
  if (title) button.title = title;
  if (iconName) button.append(icon(iconName, "domain-row-icon"));
  button.append(node("span", "domain-row-label", label));
  button.addEventListener("click", onClick);
  return button;
}

function sectionHeading(text) {
  return node("h2", "domain-sidebar-heading", text);
}

function noContent(title, copy, iconName = "sparkle") {
  const empty = node("section", "native-empty-state");
  empty.tabIndex = -1;
  empty.append(icon(iconName, "native-empty-icon"), node("h2", "", title), node("p", "", copy));
  return empty;
}

function contentSection(title, children, { className = "" } = {}) {
  const section = node("section", `native-detail-section ${className}`.trim());
  section.append(node("h2", "native-section-title", title));
  for (const child of Array.isArray(children) ? children : [children]) if (child) section.append(child);
  return section;
}

function valueLine(label, value, { mono = false, quiet = false } = {}) {
  const line = node("div", "native-value-line");
  line.append(node("dt", "", label));
  line.append(node("dd", `${mono ? "is-mono " : ""}${quiet ? "is-quiet" : ""}`.trim(), value || "—"));
  return line;
}

function identifierList(values, { empty = "None", label = "identifier" } = {}) {
  const list = node("div", "native-identifier-list");
  const identifiers = Array.isArray(values) ? values.map(String).filter(Boolean) : [];
  if (!identifiers.length) {
    list.append(node("span", "native-identifier-empty", empty));
    return list;
  }
  for (const value of identifiers) {
    const code = node("code", "native-identifier", value);
    code.title = `${label}: ${value}`;
    list.append(code);
  }
  return list;
}

function exactMetadataGrid(entries) {
  const grid = node("div", "native-exact-metadata-grid");
  for (const [label, values, options = {}] of entries.filter(Boolean)) {
    const item = node("section", "native-exact-metadata-item");
    item.append(node("h3", "", label));
    item.append(identifierList(values, options));
    grid.append(item);
  }
  return grid;
}

function sourceForkProvenance(source) {
  const value = source?.forkProvenance || source?.fork || source?.forkSource || null;
  if (!value || typeof value !== "object") return null;
  return {
    parentSourceID: value.parentSourceID || value.parentID || value.sourceID || null,
    parentRevision: value.parentRevision ?? value.revision ?? null,
    forkedAt: value.forkedAt || value.createdAt || value.timestamp || null,
  };
}

function sourceWorldActionPrefill(source) {
  const prefill = { sourceID: source.id };
  if (isExactID(source?.worldBindingID)) {
    prefill.worldID = source.worldBindingID;
    prefill.world = source.worldBindingID;
  }
  return prefill;
}

function nativeActionButton(label, iconName, candidates, prefill = {}, { primary = false, worldLock = null } = {}) {
  const button = node("button", primary ? "native-button native-button-primary glass-control" : "native-button");
  button.type = "button";
  if (iconName) button.append(icon(iconName, "control-icon"));
  button.append(node("span", "", label));
  button.addEventListener("click", () => openContextAction(candidates, {
    label,
    prefill,
    trigger: button,
    worldLock,
  }));
  return button;
}

function filterDomainItems(items, fields) {
  const query = String(elements.domainSearch?.value || "").trim().toLocaleLowerCase();
  if (!query) return items;
  return items.filter((item) => fields.map((field) => String(item?.[field] || "")).join(" ").toLocaleLowerCase().includes(query));
}

function agentManagerFilterState() {
  const runtime = nativeState();
  if (!runtime.agentManagerFilters) {
    runtime.agentManagerFilters = { assignment: "all", presence: "all" };
  }
  return runtime.agentManagerFilters;
}

function isAssignedAgent(agent) {
  return isExactID(agent?.worldAssignment?.worldID);
}

function isActiveAgent(agent) {
  return agent?.activePresence?.isActive === true;
}

function agentManagerProjectionAgents(agents) {
  const filters = agentManagerFilterState();
  return filterDomainItems(agents, ["name", "id"]).filter((agent) => {
    if (filters.assignment === "assigned" && !isAssignedAgent(agent)) return false;
    if (filters.assignment === "unassigned" && isAssignedAgent(agent)) return false;
    if (filters.presence === "active" && !isActiveAgent(agent)) return false;
    if (filters.presence === "inactive" && isActiveAgent(agent)) return false;
    return true;
  });
}

function compactProjectionFilterControl({ label, value, options, onChange }) {
  const anchor = node("div", "agent-filter-anchor");
  const trigger = node("button", "native-button");
  trigger.type = "button";
  trigger.setAttribute("aria-haspopup", "menu");
  trigger.setAttribute("aria-expanded", "false");
  trigger.setAttribute("aria-label", `${label}: ${value}`);
  trigger.append(node("span", "ellipsis", `${label}: ${value}`), icon("caret-down", "control-icon"));
  const menu = node("div", "floating-menu agent-filter-menu");
  menu.hidden = true;
  menu.setAttribute("role", "menu");
  menu.setAttribute("aria-label", `${label} filter`);
  for (const option of options) {
    const row = node("button", "menu-row menu-row-text-only");
    row.type = "button";
    row.setAttribute("role", "menuitemradio");
    const selected = option.value === value;
    row.setAttribute("aria-checked", selected ? "true" : "false");
    row.append(node("span", "row-title", option.label), icon("check", "menu-check", "Selected"));
    row.querySelector(".menu-check").hidden = !selected;
    row.addEventListener("click", () => {
      closeActiveSurface({ restoreFocus: false });
      onChange(option.value);
    });
    menu.append(row);
  }
  trigger.addEventListener("click", () => openSurface(trigger, menu));
  menu.addEventListener("keydown", menuKeyboard);
  anchor.append(trigger, menu);
  return anchor;
}

function settingsSections(snapshot) {
  const groups = new Map((snapshot?.groups || []).map((group) => [group.id, group]));
  const terminalSettings = [
    ...(groups.get("console")?.settings || []),
    ...(groups.get("presentation")?.settings || []),
  ];
  return [
    { id: "product", label: "Product", settings: [] },
    { id: "diagnostics", label: "Diagnostics", settings: [] },
    { id: "agents", label: "Agent defaults", settings: groups.get("agents")?.settings || [] },
    { id: "runtime", label: "Runtime limits", settings: groups.get("runtime")?.settings || [] },
    { id: "adapters", label: "AI adapters", settings: [] },
    { id: "terminal", label: "Terminal", settings: terminalSettings },
    { id: "advanced", label: "Advanced", settings: [] },
  ];
}

function renderDomainSidebar(view, snapshot) {
  clearNode(elements.domainSidebarContent);
  clearNode(elements.domainSidebarAction);
  const selected = nativeState().domainSelections[view] || {};
  if (!snapshot) return;
  if (view === "agentManager") {
    const filters = agentManagerFilterState();
    const filterControls = node("div", "domain-sidebar-action-stack");
    filterControls.append(
      compactProjectionFilterControl({
        label: "Assignment",
        value: {
          all: "All",
          assigned: "Assigned",
          unassigned: "Unassigned",
        }[filters.assignment] || "All",
        options: [
          { value: "all", label: "All" },
          { value: "assigned", label: "Assigned" },
          { value: "unassigned", label: "Unassigned" },
        ],
        onChange: (assignment) => {
          filters.assignment = assignment;
          renderDomainSidebar("agentManager", snapshot);
        },
      }),
      compactProjectionFilterControl({
        label: "State",
        value: {
          all: "All states",
          active: "Active",
          inactive: "Inactive",
        }[filters.presence] || "All states",
        options: [
          { value: "all", label: "All states" },
          { value: "active", label: "Active" },
          { value: "inactive", label: "Inactive" },
        ],
        onChange: (presence) => {
          filters.presence = presence;
          renderDomainSidebar("agentManager", snapshot);
        },
      }),
    );
    elements.domainSidebarContent.append(filterControls);
    const agents = agentManagerProjectionAgents(snapshot.agents);
    elements.domainSidebarContent.append(sectionHeading("Agents"));
    const list = node("div", "domain-entity-list");
    for (const agent of agents) {
      const row = node("button", "domain-entity-row agent-domain-row");
      row.type = "button";
      row.classList.toggle("is-selected", selected.agent === agent.id);
      if (selected.agent === agent.id) row.setAttribute("aria-current", "page");
      row.append(domainIconMark(agent.visual), node("span", "domain-row-label", agent.name));
      if (agent.activePresence?.isActive) row.append(node("span", "domain-presence", "Active"));
      const unreadCount = Number(agent.notifications?.unreadCount ?? agent.activePresence?.notifications?.unreadCount ?? 0);
      if (Number.isFinite(unreadCount) && unreadCount > 0) {
        row.append(node("span", "domain-unread-count", `${Math.trunc(unreadCount)} unread`));
      }
      row.addEventListener("click", () => selectDomainEntity("agentManager", { agent: agent.id }));
      list.append(row);
    }
    if (!agents.length) list.append(node("p", "domain-sidebar-empty", "No agents yet."));
    elements.domainSidebarContent.append(list);
    elements.domainSidebarAction.append(nativeActionButton("New agent", "user-plus", NATIVE_ACTION_CANDIDATES.newAgent, {}, { primary: true }));
    return;
  }
  if (view === "inventory") {
    const folders = filterDomainItems(snapshot.folders, ["name"]);
    const sources = filterDomainItems(snapshot.sources, ["name", "packageID"]);
    const folderByID = new Map(folders.map((folder) => [folder.id, folder]));
    const children = new Map();
    for (const folder of folders) {
      const parent = folder.parentID && folderByID.has(folder.parentID) ? folder.parentID : "root";
      if (!children.has(parent)) children.set(parent, []);
      children.get(parent).push(folder);
    }
    const byFolder = new Map();
    for (const source of sources) {
      const parent = source.folderID && folderByID.has(source.folderID) ? source.folderID : "root";
      if (!byFolder.has(parent)) byFolder.set(parent, []);
      byFolder.get(parent).push(source);
    }
    const appendSources = (folderID, depth) => {
      for (const source of byFolder.get(folderID) || []) {
        const row = node("button", "domain-entity-row source-domain-row");
        row.type = "button";
        row.classList.toggle("is-selected", selected.source === source.id);
        if (selected.source === source.id) row.setAttribute("aria-current", "page");
        row.style.setProperty("--tree-depth", String(Math.min(depth, 5)));
        row.append(domainIconMark(source.visual), node("span", "domain-row-label", source.name));
        if (!source.readiness?.isReady) row.append(node("span", "domain-readiness-dot", "Needs setup"));
        row.addEventListener("click", () => selectDomainEntity("inventory", { source: source.id, folder: null }));
        elements.domainSidebarContent.append(row);
      }
    };
    const appendFolder = (parentID, depth) => {
      for (const folder of children.get(parentID) || []) {
        const row = domainButton(folder.name, "folder", () => selectDomainEntity("inventory", { folder: folder.id, source: null }), {
          selected: selected.folder === folder.id,
          title: `${folder.sourceCount || 0} sources`,
        });
        row.style.setProperty("--tree-depth", String(Math.min(depth, 4)));
        row.classList.add("domain-tree-row");
        elements.domainSidebarContent.append(row);
        appendSources(folder.id, depth + 1);
        appendFolder(folder.id, depth + 1);
      }
    };
    elements.domainSidebarContent.append(sectionHeading("Inventory"));
    appendSources("root", 0);
    appendFolder("root", 0);
    const rootSources = sources.filter((source) => !source.folderID || !folderByID.has(source.folderID));
    if (!folders.length && !rootSources.length) elements.domainSidebarContent.append(node("p", "domain-sidebar-empty", "No Inventory sources yet."));
    const actions = node("div", "domain-sidebar-action-stack");
    actions.append(
      nativeActionButton("New source", "plus", NATIVE_ACTION_CANDIDATES.newSource, {}, { primary: true }),
      nativeActionButton("New folder", "folder-plus", NATIVE_ACTION_CANDIDATES.newFolder),
    );
    elements.domainSidebarAction.append(actions);
    return;
  }
  if (view === "packages") {
    const packageValues = filterDomainItems(snapshot.packages, ["displayName", "id", "version"]);
    const visibleRetained = filterDomainItems(snapshot.retainedPackages.filter((item) => item.visible), ["displayName", "id", "version"]);
    const hiddenRetained = filterDomainItems(snapshot.retainedPackages.filter((item) => !item.visible), ["displayName", "id", "version"]);
    const installed = deduplicatePackages([
      ...packageValues.filter((item) => item.isInstalled),
      ...visibleRetained,
    ]);
    const installedKeys = new Set(installed.map((item) => `${item.id}@${item.version}`));
    const available = packageValues.filter((item) => !item.isInstalled && !installedKeys.has(`${item.id}@${item.version}`));
    const key = selected.packageKey;
    const appendGroup = (title, values, iconName) => {
      elements.domainSidebarContent.append(sectionHeading(title));
      const list = node("div", "domain-entity-list");
      for (const item of values) {
        const row = domainButton(item.displayName || item.id, iconName, () => selectDomainEntity("packages", { packageKey: `${item.id}@${item.version}` }), {
          selected: key === `${item.id}@${item.version}`,
          title: `${item.id}@${item.version}`,
        });
        row.append(node("code", "domain-row-meta", item.version));
        list.append(row);
      }
      if (!values.length) list.append(node("p", "domain-sidebar-empty", "None available."));
      elements.domainSidebarContent.append(list);
    };
    appendGroup("Available", available, "package");
    appendGroup("Installed", installed, "package");
    if (hiddenRetained.length) appendGroup("Retained", hiddenRetained, "archive");
    elements.domainSidebarAction.append(nativeActionButton("Install package", "plus", NATIVE_ACTION_CANDIDATES.installPackage, {}, { primary: true }));
    return;
  }
  if (view === "templates") {
    const templates = filterDomainItems(snapshot.templates, ["displayName", "id", "version"]);
    elements.domainSidebarContent.append(sectionHeading("Trusted templates"));
    const list = node("div", "domain-entity-list");
    for (const template of templates) {
      const key = `${template.id}@${template.version}`;
      const row = domainButton(template.displayName || template.id, "file-text", () => selectDomainEntity("templates", { templateKey: key }), {
        selected: selected.templateKey === key,
        title: key,
      });
      row.append(node("code", "domain-row-meta", template.version));
      list.append(row);
    }
    if (!templates.length) list.append(node("p", "domain-sidebar-empty", "No trusted templates are installed."));
    elements.domainSidebarContent.append(list);
    return;
  }
  if (view === "settings") {
    elements.domainSidebarContent.append(sectionHeading("Settings"));
    const list = node("div", "domain-entity-list");
    for (const group of settingsSections(snapshot)) {
      const row = domainButton(group.label, settingsIcon(group.id), () => selectDomainEntity("settings", { setting: group.id }), {
        selected: selected.setting === group.id,
      });
      list.append(row);
    }
    elements.domainSidebarContent.append(list);
    const actions = node("div", "domain-sidebar-action-stack");
    actions.append(
      nativeActionButton("Validate settings", "check-circle", NATIVE_ACTION_CANDIDATES.validateSettings),
      nativeActionButton("Diagnostics", "stethoscope", NATIVE_ACTION_CANDIDATES.diagnostics),
    );
    elements.domainSidebarAction.append(actions);
  }
}

function deduplicatePackages(values) {
  const seen = new Set();
  return values.filter((item) => {
    const key = `${item.id}@${item.version}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function folderPathDepth(folder, folders) {
  let current = folder;
  let depth = 0;
  const seen = new Set();
  while (current?.parentID && folders.has(current.parentID) && !seen.has(current.parentID)) {
    seen.add(current.parentID);
    current = folders.get(current.parentID);
    depth += 1;
  }
  return depth;
}

function settingsIcon(id) {
  const value = String(id || "").toLocaleLowerCase();
  if (/diagnostic|runtime/.test(value)) return "pulse";
  if (/agent/.test(value)) return "users";
  if (/terminal|console/.test(value)) return "terminal-window";
  if (/adapter|ai/.test(value)) return "sparkle";
  return "gear-six";
}

function renderDomainView() {
  const view = state.webView;
  if (view === "world") return;
  if (state.activeWorkspaceScrollKey?.startsWith(`${view}:`)) {
    rememberWorkspaceScroll(view, state.activeWorkspaceScrollKey);
  }
  const scrollKey = workspaceScrollKey(view);
  const snapshot = domainSnapshotFor(view);
  const status = nativeState().domainStatus;
  const meta = WEB_VIEW_META[view] || WEB_VIEW_META.agentManager;
  elements.workspaceEyebrow.textContent = "mikrokhoros Web";
  elements.workspaceTitle.textContent = meta.label;
  elements.workspaceDescription.textContent = meta.description;
  elements.workspaceState.hidden = !status.loading && !status.error;
  elements.workspaceState.classList.toggle("is-error", Boolean(status.error));
  elements.workspaceState.textContent = status.error || (status.loading ? `Loading ${meta.label}…` : "");
  renderDomainSidebar(view, snapshot);
  clearNode(elements.webCapabilityContextActions);
  clearNode(elements.workspaceContent);
  if (status.loading && !snapshot) {
    elements.workspaceContent.append(noContent("Loading", `Reading ${meta.label.toLocaleLowerCase()} from the local product.`, "circle-notch"));
    state.activeWorkspaceScrollKey = scrollKey;
    restoreWorkspaceScroll(view, scrollKey);
    return;
  }
  if (status.error && !snapshot) {
    elements.workspaceContent.append(noContent("Unavailable", status.error, "warning-circle"));
    state.activeWorkspaceScrollKey = scrollKey;
    restoreWorkspaceScroll(view, scrollKey);
    return;
  }
  if (!snapshot) {
    state.activeWorkspaceScrollKey = scrollKey;
    restoreWorkspaceScroll(view, scrollKey);
    return;
  }
  if (view === "agentManager") renderAgentManager(snapshot);
  if (view === "inventory") renderDomainInventory(snapshot);
  if (view === "packages") renderPackages(snapshot);
  if (view === "templates") renderTemplates(snapshot);
  if (view === "settings") renderSettings(snapshot);
  installGlassSurfaces();
  state.activeWorkspaceScrollKey = scrollKey;
  restoreWorkspaceScroll(view, scrollKey);
}

function renderDetailHeader({ visual, title, subtitle, meta = [], actions = [] }) {
  const header = node("header", "native-entity-header");
  header.tabIndex = -1;
  if (visual) header.append(domainIconMark(visual, "native-entity-symbol"));
  const copy = node("div", "native-entity-copy");
  copy.append(node("h2", "", title));
  if (subtitle) copy.append(node("p", "native-entity-subtitle", subtitle));
  if (meta.length) {
    const values = node("div", "native-entity-meta");
    for (const item of meta.filter(Boolean)) values.append(node("span", "", item));
    copy.append(values);
  }
  header.append(copy);
  if (actions.length) {
    const actionRow = node("div", "native-entity-actions");
    actionRow.append(...actions);
    header.append(actionRow);
  }
  return header;
}

function renderAgentManager(snapshot) {
  const selected = nativeState().domainSelections.agentManager?.agent;
  const agent = snapshot.agents.find((item) => item.id === selected) || snapshot.agents[0];
  elements.webCapabilityContextActions.append(nativeActionButton("New agent", "user-plus", NATIVE_ACTION_CANDIDATES.newAgent, {}, { primary: true }));
  if (!agent) {
    elements.workspaceContent.append(noContent("No agents", "Create an identity to make it available to Worlds.", "user-plus"));
    return;
  }
  const presence = agent.activePresence || {};
  const notifications = agent.notifications || presence.notifications || {};
  const unreadCount = Number(notifications.unreadCount || 0);
  const location = presence.isActive
    ? [presence.worldName || "World", presence.coordinate ? `(${presence.coordinate.x},${presence.coordinate.y})` : ""].filter(Boolean).join(" · ")
    : "Not active in a World";
  const identityActions = [
    nativeActionButton("Configure", "sliders-horizontal", NATIVE_ACTION_CANDIDATES.configureAgent, { agentID: agent.id }),
    nativeActionButton("Edit profile", "identification-card", NATIVE_ACTION_CANDIDATES.profileAgent, { agentID: agent.id }),
  ];
  if (agent.hasProfile) {
    identityActions.push(nativeActionButton("Clear profile", "x", NATIVE_ACTION_CANDIDATES.clearAgentProfile, { agentID: agent.id }));
  }
  if (notifications.canRetry === true) {
    identityActions.push(nativeActionButton("Retry", "circle-notch", NATIVE_ACTION_CANDIDATES.retryAgent, { agentID: agent.id }));
  }
  if (presence.isActive) {
    identityActions.push(nativeActionButton("Leave World", "x", NATIVE_ACTION_CANDIDATES.removeAgent, {
      agentID: agent.id,
      worldID: presence.worldID,
    }));
  } else {
    identityActions.push(nativeActionButton("Place in World", "globe", ["agentAdd"], { agentID: agent.id }));
  }
  if (agent.worldAssignment?.worldID) {
    identityActions.push(nativeActionButton("Open action session", "terminal-window", NATIVE_ACTION_CANDIDATES.agentSession, { agentID: agent.id }));
    const worldLink = node("button", "native-button");
    worldLink.type = "button";
    worldLink.append(icon("globe", "control-icon"), node("span", "", "Open assigned World"));
    worldLink.addEventListener("click", () => openNativeWorldEntity(agent.worldAssignment.worldID));
    identityActions.push(worldLink);
  }
  elements.workspaceContent.append(renderDetailHeader({
    visual: agent.visual,
    title: agent.name,
    subtitle: location,
    meta: [agent.hasProfile ? "Profile configured" : "No profile", `Created ${compactDate(agent.createdAt)}`],
    actions: identityActions,
  }));
  const overview = node("dl", "native-detail-grid");
  overview.append(
    valueLine("Agent ID", agent.id, { mono: true }),
    valueLine("Assignment", agent.worldAssignment?.worldName || (agent.worldAssignment ? "Assigned World" : "Unassigned")),
    valueLine("Action limit", `${agent.maximumActionsPerResponse} per response`),
    valueLine("Presence", presence.isActive ? "Active" : "Inactive"),
    valueLine("Unread notifications", Number.isFinite(unreadCount) ? String(Math.max(0, Math.trunc(unreadCount))) : "0"),
    valueLine("Container", presence.containerID || "Not placed", { mono: Boolean(presence.containerID) }),
    valueLine("Primary holding", presence.primaryHoldingID || "Empty", { mono: Boolean(presence.primaryHoldingID) }),
    valueLine("Updated", compactDate(agent.updatedAt)),
  );
  elements.workspaceContent.append(contentSection("Identity", overview));
  const holdings = Array.isArray(presence.holdings) ? presence.holdings : [];
  if (holdings.length) {
    const list = node("div", "native-chip-grid");
    for (const holding of holdings) {
      const item = holding.objectID && isExactID(presence.worldID)
        ? node("button", "native-holding native-linked-card")
        : node("div", "native-holding");
      if (item instanceof HTMLButtonElement) {
        item.type = "button";
        item.addEventListener("click", () => openNativeWorldEntity(presence.worldID, holding.objectID));
      }
      if (holding.visual) item.append(domainIconMark(holding.visual, "native-chip-symbol"));
      item.append(node("span", "native-holding-slot", holding.slot || "Slot"), node("span", "native-holding-name", holding.name || "Empty"));
      list.append(item);
    }
    elements.workspaceContent.append(contentSection("Holdings", list));
  }
  const lifecycle = Array.isArray(presence.lifecycle) ? presence.lifecycle : [];
  if (lifecycle.length) {
    const list = node("div", "native-lifecycle-grid");
    for (const item of lifecycle) {
      const card = item.id && isExactID(presence.worldID)
        ? node("button", "native-lifecycle-card native-linked-card")
        : node("article", "native-lifecycle-card");
      if (card instanceof HTMLButtonElement) {
        card.type = "button";
        card.addEventListener("click", () => openNativeWorldEntity(presence.worldID, item.id));
      }
      if (item.visual) card.append(domainIconMark(item.visual, "native-chip-symbol"));
      card.append(node("h3", "", item.label || item.role || "Equipment"));
      if (item.name) card.append(node("p", "", item.name));
      list.append(card);
    }
    elements.workspaceContent.append(contentSection("Agent equipment", list));
  }
}

async function openNativeWorldEntity(worldID, objectID = null) {
  if (!isExactID(worldID)) return;
  switchWebView("world", { historyMode: null });
  updateRoute({ world: worldID }, "push");
  const opened = await loadWorld({ route: { world: worldID }, mode: "reset-human" });
  if (opened && isExactID(objectID)) await openObject(objectID, elements.appViewTrigger);
}

function renderDomainInventory(snapshot) {
  const selected = nativeState().domainSelections.inventory || {};
  const source = snapshot.sources.find((item) => item.id === selected.source) || null;
  const folder = snapshot.folders.find((item) => item.id === selected.folder) || null;
  elements.webCapabilityContextActions.append(nativeActionButton("New source", "plus", NATIVE_ACTION_CANDIDATES.newSource, {}, { primary: true }));
  if (folder && !source) {
    const items = snapshot.sources.filter((item) => item.folderID === folder.id);
    elements.workspaceContent.append(renderDetailHeader({
      title: folder.name,
      subtitle: `${folder.sourceCount || items.length} source${(folder.sourceCount || items.length) === 1 ? "" : "s"}`,
      actions: [
        nativeActionButton("New source", "plus", NATIVE_ACTION_CANDIDATES.newSource, { folderID: folder.id }),
        nativeActionButton("Rename", "pencil-simple", NATIVE_ACTION_CANDIDATES.renameFolder, { folderID: folder.id }),
        nativeActionButton("Move", "arrow-square-out", NATIVE_ACTION_CANDIDATES.moveFolder, { folderID: folder.id }),
        nativeActionButton("Delete", "trash", NATIVE_ACTION_CANDIDATES.deleteFolder, { folderID: folder.id }),
      ],
    }));
    if (items.length) {
      const list = node("div", "native-list-card");
      for (const item of items) {
        const row = node("button", "native-list-row");
        row.type = "button";
        row.append(domainIconMark(item.visual, "native-list-symbol"), node("span", "native-list-title", item.name), node("code", "native-list-meta", `${item.packageID}@${item.packageVersion}`));
        row.addEventListener("click", () => selectDomainEntity("inventory", { source: item.id, folder: null }));
        list.append(row);
      }
      elements.workspaceContent.append(contentSection("Sources", list));
    } else elements.workspaceContent.append(noContent("No sources here", "Create a source in this folder, then configure it for a World.", "archive"));
    return;
  }
  if (!source) {
    elements.workspaceContent.append(noContent("No Inventory sources", "Add a user-owned source to configure and deploy objects.", "archive"));
    return;
  }
  const readiness = source.readiness || {};
  const sourceMeta = [`${source.packageID}@${source.packageVersion}`, readiness.isReady ? "Ready" : "Needs setup"];
  const management = source.management || {};
  const inventoryManagement = {
    ...management,
    actions: (Array.isArray(management.actions) ? management.actions : [])
      .filter((entry) => managementScopeAccepts(entry, "inventory")),
    views: (Array.isArray(management.views) ? management.views : [])
      .filter((entry) => managementScopeAccepts(entry, "inventory")),
  };
  const hasObjectInterface = ["fields", "actions", "views", "reports"]
    .some((key) => Array.isArray(inventoryManagement[key]) && inventoryManagement[key].length > 0);
  const sourceActions = [
    ...(hasObjectInterface
      ? [nativeActionButton("Object interface", "cube", ["__object_interface__"], { sourceID: source.id })]
      : []),
    nativeActionButton("Fork for World…", "globe", NATIVE_ACTION_CANDIDATES.forkSource, { sourceID: source.id }),
    nativeActionButton("Deploy…", "arrow-square-out", NATIVE_ACTION_CANDIDATES.deploySource, { sourceID: source.id }),
    nativeActionButton("Move", "arrow-square-out", NATIVE_ACTION_CANDIDATES.moveSource, { sourceID: source.id }),
    nativeActionButton("Remove", "trash", NATIVE_ACTION_CANDIDATES.removeSource, { sourceID: source.id }),
  ];
  elements.workspaceContent.append(renderDetailHeader({
    visual: source.visual,
    title: source.name,
    subtitle: readiness.isReady ? "Ready to use" : "Complete setup before deployment",
    meta: sourceMeta,
    actions: sourceActions,
  }));
  const summary = node("dl", "native-detail-grid");
  summary.append(
    valueLine("Source ID", source.id, { mono: true }),
    valueLine("Package", `${source.packageID}@${source.packageVersion}`, { mono: true }),
    valueLine("Package content hash", source.packageHash || "—", { mono: true }),
    valueLine("Folder", source.folderID, { mono: true }),
    valueLine("Revision", source.revision || "Current"),
    valueLine("Configuration", `${source.configurationFieldIDs?.length || 0} field${(source.configurationFieldIDs?.length || 0) === 1 ? "" : "s"}`),
    valueLine("Credentials", `${source.credentialFieldIDs?.length || 0} required`),
    valueLine("Capabilities", `${source.grantedCapabilityIDs?.length || 0} granted · ${source.requestedCapabilityIDs?.length || 0} requested`),
    valueLine("World binding", source.worldBindingID || "Reusable", { mono: Boolean(source.worldBindingID) }),
    valueLine("Template lineage", source.templateSource ? `${source.templateSource.templateID}@${source.templateSource.templateVersion}` : "Independent"),
    valueLine("Updated", compactDate(source.updatedAt)),
  );
  elements.workspaceContent.append(contentSection("Source", summary));
  const sourceContract = exactMetadataGrid([
    ["Requested capabilities", source.requestedCapabilityIDs, { empty: "No requested capabilities", label: "capability" }],
    ["Granted capabilities", source.grantedCapabilityIDs, { empty: "No granted capabilities", label: "capability" }],
    ["Configured field IDs", source.configurationFieldIDs, { empty: "No configured fields", label: "field" }],
    ["Credential field IDs", source.credentialFieldIDs, { empty: "No credentials stored", label: "credential field" }],
  ]);
  elements.workspaceContent.append(contentSection("Exact source state", sourceContract));
  const fork = sourceForkProvenance(source);
  if (fork && (fork.parentSourceID || fork.parentRevision !== null || fork.forkedAt)) {
    const provenance = node("dl", "native-detail-grid");
    provenance.append(
      valueLine("Parent source", fork.parentSourceID || "—", { mono: Boolean(fork.parentSourceID) }),
      valueLine("Parent revision", fork.parentRevision === null || fork.parentRevision === undefined ? "—" : String(fork.parentRevision)),
      valueLine("Forked", compactDate(fork.forkedAt)),
    );
    elements.workspaceContent.append(contentSection("Fork provenance", provenance));
  }
  if (!readiness.isReady) {
    const readinessContent = node("div", "native-readiness-detail");
    const needs = node("div", "native-notice native-notice-warning");
    needs.append(icon("warning-circle", "native-notice-icon"), node("p", "", "This source still needs the exact items below before deployment."));
    readinessContent.append(needs, exactMetadataGrid([
      ["Missing configuration", readiness.missingConfigurationFieldIDs, { empty: "No missing configuration", label: "field" }],
      ["Missing credentials", readiness.missingCredentialFieldIDs, { empty: "No missing credentials", label: "credential field" }],
      ["Missing capabilities", readiness.missingCapabilityIDs, { empty: "No missing capabilities", label: "capability" }],
    ]));
    elements.workspaceContent.append(contentSection("Readiness", readinessContent));
  }
  const accessActions = node("div", "settings-action-grid");
  accessActions.append(
    nativeActionButton("Review capabilities", "shield", NATIVE_ACTION_CANDIDATES.listCapabilities, { sourceID: source.id }),
    nativeActionButton("Grant", "plus", NATIVE_ACTION_CANDIDATES.grantCapability, { sourceID: source.id }),
    nativeActionButton("Revoke", "x", NATIVE_ACTION_CANDIDATES.revokeCapability, { sourceID: source.id }),
  );
  elements.workspaceContent.append(contentSection("Access", accessActions));

  const worldActivity = node("div", "native-world-activity");
  const activityCopy = node("p", "native-world-activity-copy");
  const binding = isExactID(source.worldBindingID);
  activityCopy.textContent = binding
    ? `This fork is bound to World ${source.worldBindingID}. Each activity command uses that exact World.`
    : "Each activity command asks for one exact World when it opens. It does not change the World workspace.";
  worldActivity.append(activityCopy);
  const worldActivityActions = node("div", "settings-action-grid");
  const activityPrefill = sourceWorldActionPrefill(source);
  worldActivityActions.append(
    nativeActionButton("Copies", "cube", NATIVE_ACTION_CANDIDATES.copiesSource, activityPrefill, { worldLock: source.worldBindingID }),
    nativeActionButton("Listeners", "circle-notch", NATIVE_ACTION_CANDIDATES.listenersSource, activityPrefill, { worldLock: source.worldBindingID }),
    nativeActionButton("Reports", "file-text", NATIVE_ACTION_CANDIDATES.reportsSource, activityPrefill, { worldLock: source.worldBindingID }),
    nativeActionButton("Follow reports", "bell", NATIVE_ACTION_CANDIDATES.followReportsSource, activityPrefill, { worldLock: source.worldBindingID }),
    nativeActionButton("Restocking", "archive", NATIVE_ACTION_CANDIDATES.restockSource, activityPrefill, { worldLock: source.worldBindingID }),
    nativeActionButton("New restock rule", "plus", NATIVE_ACTION_CANDIDATES.createRestockSource, activityPrefill, { worldLock: source.worldBindingID }),
  );
  worldActivity.append(worldActivityActions);
  elements.workspaceContent.append(contentSection("World activity", worldActivity));
  const objectInterface = renderObjectInterface(source, inventoryManagement);
  if (objectInterface) elements.workspaceContent.append(objectInterface);
}

function renderObjectInterface(source, management) {
  const fields = Array.isArray(management.fields) ? management.fields : [];
  const actions = (Array.isArray(management.actions) ? management.actions : [])
    .filter((entry) => managementScopeAccepts(entry, "inventory"));
  const views = (Array.isArray(management.views) ? management.views : [])
    .filter((entry) => managementScopeAccepts(entry, "inventory"));
  const reports = Array.isArray(management.reports) ? management.reports : [];
  const hostPathRestricted = managementContractUsesHostPaths(management);
  if (!fields.length && !actions.length && !views.length && !reports.length) return null;
  const root = node("div", "object-interface-inline");
  root.append(node("p", "object-interface-copy", "Controls below come from this source’s declared object interface."));
  if (fields.length) {
    root.append(contentSection(
      "Fields",
      renderManagementFields({ scope: "inventory", source, entries: fields }),
      { className: "object-interface-section" },
    ));
  }
  if (actions.length) {
    root.append(contentSection(
      "Actions",
      renderManagementActions({
        scope: "inventory",
        source,
        entries: actions,
        hostPathRestricted,
      }),
      { className: "object-interface-section" },
    ));
  }
  if (views.length) {
    root.append(contentSection(
      "Views",
      renderManagementViews({
        scope: "inventory",
        source,
        entries: views,
        hostPathRestricted,
      }),
      { className: "object-interface-section" },
    ));
  }
  if (reports.length) {
    root.append(contentSection(
      "Reports",
      renderManagementReports(reports),
      { className: "object-interface-section" },
    ));
  }
  return contentSection("Object interface", root, { className: "native-object-interface" });
}

function managementScopeAccepts(entry, scope) {
  const value = String(entry?.scope || "inventory").toLocaleLowerCase();
  return value === "both" || value === scope;
}

function managementValue(source, ...keys) {
  for (const key of keys) {
    if (source && Object.prototype.hasOwnProperty.call(source, key)) return source[key];
  }
  return undefined;
}

function managementValueText(value) {
  if (value === null || value === undefined) return "";
  if (typeof value === "string") return value;
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  return JSON.stringify(value);
}

function managementFieldStatus(source, field) {
  if (!source || !field) return field?.required ? "Required" : "Optional";
  const configured = new Set(source.configurationFieldIDs || []);
  const credentials = new Set(source.credentialFieldIDs || []);
  const present = field.kind === "secret" ? credentials.has(field.id) : configured.has(field.id);
  if (present) return "Set";
  return field.required ? "Required" : "Optional";
}

function managementSchemaRows(schema, { empty = "No values declared." } = {}) {
  const entries = Object.entries(schema && typeof schema === "object" ? schema : {});
  const list = node("div", "management-schema-list");
  if (!entries.length) {
    list.append(node("span", "management-schema-empty", empty));
    return list;
  }
  for (const [id, kind] of entries) {
    const row = node("div", "management-schema-row");
    row.append(node("code", "management-schema-id", id), node("span", "management-schema-kind", formatKey(kind)));
    list.append(row);
  }
  return list;
}

function managementDefinition(items) {
  const list = node("dl", "management-definition");
  for (const item of items.filter(Boolean)) {
    const [label, value, options = {}] = item;
    const row = node("div", "management-definition-row");
    row.append(node("dt", "", label));
    const detail = node("dd", options.mono ? "is-mono" : "");
    if (value instanceof Node) detail.append(value);
    else detail.textContent = value === "" || value === undefined || value === null ? "—" : String(value);
    row.append(detail);
    list.append(row);
  }
  return list;
}

function managementChoiceText(values, empty = "No fixed choices") {
  const choices = Array.isArray(values) ? values.map(String).filter(Boolean) : [];
  return choices.length ? choices.join(" · ") : empty;
}

function managementInputSchema(action) {
  const types = managementValue(action, "inputTypes", "input_types") || {};
  const defaults = managementValue(action, "inputDefaults", "input_defaults") || {};
  const choices = managementValue(action, "inputChoices", "input_choices") || {};
  const list = node("div", "management-input-schema");
  const parameters = Array.isArray(action?.parameters) ? action.parameters : [];
  if (!parameters.length) {
    list.append(node("span", "management-schema-empty", "No input required."));
    return list;
  }
  for (const parameter of parameters) {
    const row = node("div", "management-input-schema-row");
    const identity = node("div", "management-input-schema-identity");
    identity.append(
      node("code", "management-schema-id", parameter),
      node("span", "management-schema-kind", formatKey(types[parameter] || "text")),
    );
    const constraints = [];
    if (Object.prototype.hasOwnProperty.call(defaults, parameter)) {
      constraints.push(`Default: ${managementValueText(defaults[parameter])}`);
    }
    if (Array.isArray(choices[parameter]) && choices[parameter].length) {
      constraints.push(`Choices: ${managementChoiceText(choices[parameter])}`);
    }
    row.append(identity);
    if (constraints.length) row.append(node("span", "management-input-schema-detail", constraints.join(" · ")));
    list.append(row);
  }
  return list;
}

function managementFieldConstraints(field) {
  const constraints = [];
  const minimum = managementValue(field, "minimum");
  const maximum = managementValue(field, "maximum");
  const minimumCharacters = managementValue(field, "minimumCharacters", "minimum_characters");
  const maximumCharacters = managementValue(field, "maximumCharacters", "maximum_characters");
  const defaultValue = managementValue(field, "defaultValue", "default");
  if (Number.isFinite(minimum)) constraints.push(`Minimum: ${minimum}`);
  if (Number.isFinite(maximum)) constraints.push(`Maximum: ${maximum}`);
  if (Number.isInteger(minimumCharacters)) constraints.push(`Min length: ${minimumCharacters}`);
  if (Number.isInteger(maximumCharacters)) constraints.push(`Max length: ${maximumCharacters}`);
  if (Array.isArray(field.choices) && field.choices.length) constraints.push(`Choices: ${managementChoiceText(field.choices)}`);
  if (defaultValue !== null && defaultValue !== undefined) {
    constraints.push(`Declared default: ${managementValueText(defaultValue)}`);
  }
  return constraints;
}

function managementContractUsesHostPaths(management) {
  const fields = Array.isArray(management?.fields) ? management.fields : [];
  if (fields.some((field) => String(field?.kind || "").toLocaleLowerCase() === "path")) return true;
  const actions = Array.isArray(management?.actions) ? management.actions : [];
  return actions.some((action) => {
    const inputTypes = managementValue(action, "inputTypes", "input_types") || {};
    return Object.values(inputTypes)
      .some((value) => String(value).toLocaleLowerCase() === "path");
  });
}

function managementViewIsCLIOnly(view, hostPathRestricted) {
  return hostPathRestricted
    || String(view?.source || "").toLocaleLowerCase() === "configuration";
}

function renderManagementFields({ scope, source, entries }) {
  const list = node("div", "native-interface-list");
  for (const field of Array.isArray(entries) ? entries : []) {
    const row = node("div", "native-interface-row management-contract-row");
    const copy = node("div", "management-contract-copy");
    copy.append(node("span", "native-interface-label", field.label || formatKey(field.id || "Field")));
    if (field.summary) copy.append(node("span", "management-contract-summary", field.summary));
    const metadata = node("div", "management-contract-meta");
    metadata.append(
      node("span", "native-chip", formatKey(field.kind || "text")),
      node("span", "native-interface-kind", managementFieldStatus(source, field)),
    );
    if (scope === "inventory") {
      const usesHostPath = String(field.kind || "").toLocaleLowerCase() === "path";
      if (usesHostPath) {
        metadata.append(node("span", "native-chip", "CLI only"));
      } else {
        const button = node("button", "native-button native-button-quiet");
        button.type = "button";
        button.append(
          icon(field.kind === "secret" ? "key" : "pencil-simple", "control-icon"),
          node("span", "", field.kind === "secret" ? "Set credential" : "Set value"),
        );
        button.addEventListener("click", () => openManagementFieldForm(source, field, button));
        metadata.append(button);
      }
      if (field.kind === "secret" && (source.credentialFieldIDs || []).includes(field.id)) {
        const clear = node("button", "native-button native-button-quiet");
        clear.type = "button";
        clear.append(icon("x", "control-icon"), node("span", "", "Clear"));
        clear.addEventListener("click", () => openContextAction(
          NATIVE_ACTION_CANDIDATES.clearCredentialSource,
          { label: `Clear ${field.label || formatKey(field.id)}`, prefill: { sourceID: source.id, field: field.id }, trigger: clear },
        ));
        metadata.append(clear);
      }
    }
    const details = managementDefinition([
      ["Field ID", field.id, { mono: true }],
      ["Scope", scope === "inventory" ? "Inventory configuration" : "World object"],
      ["Required", field.required ? "Yes" : "No"],
      ["Deployable", field.deployable ? "Yes" : "No"],
      ["Constraints", managementFieldConstraints(field).join(" · ") || "None declared"],
    ]);
    const body = node("div", "management-contract-body");
    body.append(copy, details);
    row.append(body, metadata);
    list.append(row);
  }
  return list;
}

function renderManagementActions({ scope, source, worldID = null, entries, hostPathRestricted = false }) {
  const list = node("div", "management-contract-list");
  for (const action of (Array.isArray(entries) ? entries : []).filter((entry) => managementScopeAccepts(entry, scope))) {
    const card = node("article", "management-contract-card");
    const copy = node("div", "management-contract-copy");
    copy.append(node("h3", "", action.summary || formatKey(action.id || "Action")));
    const parameters = Array.isArray(action.parameters) ? action.parameters : [];
    copy.append(node(
      "p",
      "management-contract-summary",
      parameters.length ? `${parameters.length} input${parameters.length === 1 ? "" : "s"}` : "No input required",
    ));
    const schemas = node("div", "management-contract-schemas");
    const inputs = node("section", "management-schema-group");
    inputs.append(node("h4", "", "Input schema"), managementInputSchema(action));
    const result = node("section", "management-schema-group");
    result.append(node("h4", "", "Result schema"), managementSchemaRows(action.result, { empty: "No structured result declared." }));
    schemas.append(inputs, result);
    copy.append(managementDefinition([
      ["Action ID", action.id, { mono: true }],
      ["Scope", formatKey(action.scope || scope)],
      ["State", action.mutating ? "Mutating" : "Read-only"],
      ["Required capabilities", managementChoiceText(
        managementValue(action, "requiredCapabilityIDs", "required_capabilities"),
        "None required",
      )],
    ]), schemas);
    const inputTypes = managementValue(action, "inputTypes", "input_types") || {};
    const usesHostPath = hostPathRestricted || Object.values(inputTypes)
      .some((value) => String(value).toLocaleLowerCase() === "path");
    if (usesHostPath) {
      card.append(copy, node("span", "native-chip", "CLI only"));
    } else {
      const button = node("button", "native-button");
      button.type = "button";
      button.append(icon("arrow-right", "control-icon"), node("span", "", action.mutating ? "Run action" : "Open action"));
      button.addEventListener("click", () => openManagementActionForm({
        scope,
        source,
        worldID,
        action,
        hostPathRestricted,
        trigger: button,
      }));
      card.append(copy, button);
    }
    list.append(card);
  }
  return list;
}

function renderManagementViews({ scope, source, worldID = null, entries, hostPathRestricted = false }) {
  const list = node("div", "management-contract-list");
  for (const view of (Array.isArray(entries) ? entries : []).filter((entry) => managementScopeAccepts(entry, scope))) {
    const card = node("article", "management-contract-card");
    const copy = node("div", "management-contract-copy");
    copy.append(node("h3", "", view.summary || formatKey(view.id || "View")));
    copy.append(node("p", "management-contract-summary", `Structured ${formatKey(view.source || "summary").toLocaleLowerCase()} view`));
    const result = node("section", "management-schema-group");
    result.append(node("h4", "", "Result schema"), managementSchemaRows(view.result, { empty: "No structured result declared." }));
    copy.append(managementDefinition([
      ["View ID", view.id, { mono: true }],
      ["Scope", formatKey(view.scope || scope)],
      ["Source", view.source || "—", { mono: true }],
    ]), result);
    if (managementViewIsCLIOnly(view, hostPathRestricted)) {
      card.append(copy, node("span", "native-chip", "CLI only"));
    } else {
      const button = node("button", "native-button");
      button.type = "button";
      button.append(icon("arrow-square-out", "control-icon"), node("span", "", "Open view"));
      button.addEventListener("click", () => openManagementView({
        scope,
        source,
        worldID,
        view,
        hostPathRestricted,
        trigger: button,
      }));
      card.append(copy, button);
    }
    list.append(card);
  }
  return list;
}

function renderManagementReports(entries) {
  const list = node("div", "native-interface-list");
  for (const report of Array.isArray(entries) ? entries : []) {
    const row = node("div", "native-interface-row management-contract-row");
    const copy = node("div", "management-contract-copy");
    copy.append(node("span", "native-interface-label", report.summary || formatKey(report.type || "Report")));
    const maximumTitleCharacters = managementValue(report, "maximumTitleCharacters", "maximum_title_characters");
    const maximumBodyCharacters = managementValue(report, "maximumBodyCharacters", "maximum_body_characters");
    const maximumPayloadBytes = managementValue(report, "maximumPayloadBytes", "maximum_payload_bytes");
    copy.append(managementDefinition([
      ["Report type", report.type, { mono: true }],
      ["Title limit", `${Number(maximumTitleCharacters) || 0} characters`],
      ["Body limit", `${Number(maximumBodyCharacters) || 0} characters`],
      ["Payload limit", maximumPayloadBytes === null || maximumPayloadBytes === undefined ? "No byte limit declared" : `${maximumPayloadBytes} bytes`],
    ]));
    const payload = node("section", "management-schema-group");
    payload.append(node("h4", "", "Payload schema"), managementSchemaRows(report.payload, { empty: "No payload fields declared." }));
    copy.append(payload);
    row.append(copy, node("span", "native-chip", "Declared"));
    list.append(row);
  }
  return list;
}

function managementControl(field) {
  const kind = String(field.kind || "text").toLocaleLowerCase();
  const choices = Array.isArray(field.choices) ? field.choices : [];
  const defaultText = managementValueText(managementValue(field, "defaultValue", "default"));
  if (choices.length) {
    const choice = webChoiceControl({
      name: field.id,
      choices: choices.map((value) => ({ value: String(value), label: String(value), title: String(value) })),
      value: choices.map(String).includes(defaultText) ? defaultText : String(choices[0]),
      placeholder: `Choose ${field.label || formatKey(field.id)}`,
      label: `Choose ${field.label || formatKey(field.id)}`,
    });
    return { root: choice.root, control: choice.input };
  }
  if (kind === "boolean") {
    const root = node("label", "boolean-field management-boolean-field");
    const control = node("input");
    control.type = "checkbox";
    control.name = field.id;
    control.checked = defaultText.toLocaleLowerCase() === "true";
    root.append(control, node("span", "", field.summary || field.label || formatKey(field.id)));
    return { root, control };
  }
  const control = node("input", "web-input");
  control.name = field.id;
  control.type = kind === "integer" || kind === "decimal" ? "number" : kind === "url" ? "url" : "text";
  if (kind === "integer") control.step = "1";
  if (kind === "decimal") control.step = "any";
  if (Number.isFinite(field.minimum)) control.min = String(field.minimum);
  if (Number.isFinite(field.maximum)) control.max = String(field.maximum);
  if (Number.isInteger(field.minimumCharacters)) control.minLength = field.minimumCharacters;
  if (Number.isInteger(field.maximumCharacters)) control.maxLength = field.maximumCharacters;
  control.value = defaultText;
  control.autocomplete = "off";
  control.spellcheck = false;
  return { root: control, control };
}

function appendManagementFieldControl(form, field, { required = false } = {}) {
  const wrap = node("div", "generated-field");
  const header = node("span", "generated-field-header");
  header.append(
    node("span", "field-label", field.label || formatKey(field.id)),
    node("span", "field-cardinality", required ? "Required" : "Optional"),
  );
  wrap.append(header);
  const rendered = managementControl(field);
  rendered.control.required = required && rendered.control.type !== "checkbox";
  rendered.control.dataset.managementField = field.id;
  wrap.append(rendered.root);
  if (field.summary && field.kind !== "boolean") wrap.append(node("span", "field-hint", field.summary));
  form.append(wrap);
  return rendered.control;
}

function openManagementDialog({ title, summary, trigger }) {
  cancelWebActivity();
  state.actionReturnFocus = trigger || (document.activeElement instanceof HTMLElement ? document.activeElement : null);
  state.activeActionLabel = title;
  elements.actionBackdrop.hidden = false;
  elements.operationDetail.hidden = false;
  elements.operationDetail.replaceChildren();
  const heading = node("header", "operation-heading");
  const copy = node("div");
  copy.append(node("h2", "", title));
  if (summary) copy.append(node("p", "", summary));
  heading.append(copy);
  elements.operationDetail.append(heading);
  elements.actionDialog.focus({ preventScroll: true });
}

function managedCapabilityFields(descriptor, { scope, sourceID, operationID, inputs = [] }) {
  const fields = {};
  const identityField = scope === "world" ? "world-object-id" : "inventory-id";
  if (!descriptor.fields.some((field) => field.id === identityField)) throw new Error("The exact object context is unavailable.");
  fields[identityField] = [sourceID];
  if (operationID) {
    const operationField = descriptor.fields.some((field) => field.id === "action") ? "action" : "view";
    fields[operationField] = [operationID];
  }
  if (inputs.length) fields.input = inputs;
  return fields;
}

async function runManagedCapability(descriptor, { fields, worldID = null, secret = null }) {
  const controller = new AbortController();
  state.webRequest?.abort();
  state.webRequest = controller;
  let path = "/api/v1/web/execute";
  let body = { operationID: descriptor.id, ...(isExactID(worldID) ? { worldID } : {}), fields };
  if (descriptor.mode === "secret") {
    path = "/api/v1/web/secret";
    body = { ...body, secret: secret || "" };
  }
  try {
    return await fetchWebCapability(path, body, controller.signal);
  } finally {
    state.webRequest = null;
  }
}

function openManagementFieldForm(source, field, trigger) {
  if (String(field.kind || "").toLocaleLowerCase() === "path") {
    showToast("Host filesystem paths are available only in the local CLI.");
    return;
  }
  if (field.kind === "secret") {
    openContextAction(
      NATIVE_ACTION_CANDIDATES.credentialSource,
      { label: `Set ${field.label || formatKey(field.id)}`, prefill: { sourceID: source.id, field: field.id }, trigger },
    );
    return;
  }
  const descriptor = capabilityFor(NATIVE_ACTION_CANDIDATES.configureSource);
  if (!descriptor) {
    showToast("Configuration is unavailable in this local product.");
    return;
  }
  openManagementDialog({
    title: `Set ${field.label || formatKey(field.id)}`,
    summary: field.summary || "Update this declared configuration field without exposing its current value.",
    trigger,
  });
  const form = node("form", "operation-form management-operation-form");
  form.noValidate = true;
  const control = appendManagementFieldControl(form, field, { required: field.required });
  const status = node("p", "inline-status");
  status.setAttribute("role", "status");
  status.setAttribute("aria-live", "polite");
  const actions = node("div", "operation-actions");
  const save = node("button", "action-button", "Save");
  save.type = "submit";
  actions.append(save);
  if (!field.required) {
    const unset = node("button", "secondary-button", "Unset");
    unset.type = "button";
    unset.addEventListener("click", async () => {
      unset.disabled = true;
      save.disabled = true;
      status.textContent = "Removing value…";
      try {
        const result = await runManagedCapability(descriptor, {
          fields: { "inventory-id": [source.id], unset: [field.id] },
        });
        renderWebResult(descriptor, result);
        await refreshWebTargets(descriptor, result);
        status.textContent = result.accepted === false ? "Value was not removed." : "Value removed.";
      } catch (error) {
        status.textContent = error?.message || webErrorMessage(0);
        status.classList.add("is-error");
      } finally {
        unset.disabled = false;
        save.disabled = false;
      }
    });
    actions.append(unset);
  }
  const cancel = node("button", "secondary-button", "Cancel");
  cancel.type = "button";
  cancel.addEventListener("click", () => closeActionSheet());
  actions.append(cancel);
  form.append(status, actions);
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!form.reportValidity()) return;
    save.disabled = true;
    status.classList.remove("is-error");
    status.textContent = "Saving value…";
    const value = control.type === "checkbox" ? String(control.checked) : String(control.value);
    try {
      const result = await runManagedCapability(descriptor, {
        fields: { "inventory-id": [source.id], set: [`${field.id}=${value}`] },
      });
      renderWebResult(descriptor, result);
      await refreshWebTargets(descriptor, result);
      status.textContent = result.accepted === false ? "Value was not accepted." : "Value saved.";
    } catch (error) {
      status.textContent = error?.message || webErrorMessage(0);
      status.classList.add("is-error");
    } finally {
      save.disabled = false;
    }
  });
  elements.operationDetail.append(form);
  control.focus({ preventScroll: true });
}

function openManagementActionForm({
  scope,
  source,
  worldID,
  action,
  hostPathRestricted = false,
  trigger,
}) {
  const inputTypes = managementValue(action, "inputTypes", "input_types") || {};
  if (
    hostPathRestricted
    || Object.values(inputTypes).some((value) => String(value).toLocaleLowerCase() === "path")
  ) {
    showToast("Host-path management is available only in the local CLI.");
    return;
  }
  const descriptor = capabilityFor(
    scope === "world" ? NATIVE_ACTION_CANDIDATES.worldObjectAction : NATIVE_ACTION_CANDIDATES.objectAction,
  );
  if (!descriptor || !isExactID(source?.id)) {
    showToast("This object action is unavailable in the current context.");
    return;
  }
  openManagementDialog({
    title: action.summary || formatKey(action.id),
    summary: `${source.name || "Object"} · ${action.mutating ? "Changes object state" : "Reads object state"}`,
    trigger,
  });
  const form = node("form", "operation-form management-operation-form");
  form.noValidate = true;
  const controls = new Map();
  const types = managementValue(action, "inputTypes", "input_types") || {};
  const defaults = managementValue(action, "inputDefaults", "input_defaults") || {};
  const choices = managementValue(action, "inputChoices", "input_choices") || {};
  for (const parameter of Array.isArray(action.parameters) ? action.parameters : []) {
    const hasDefault = Object.prototype.hasOwnProperty.call(defaults, parameter);
    const field = {
      id: parameter,
      label: formatKey(parameter),
      summary: "",
      kind: types[parameter] || "text",
      defaultValue: hasDefault ? defaults[parameter] : undefined,
      choices: choices[parameter] || [],
    };
    controls.set(parameter, appendManagementFieldControl(form, field, { required: !hasDefault }));
  }
  const status = node("p", "inline-status");
  status.setAttribute("role", "status");
  status.setAttribute("aria-live", "polite");
  const actions = node("div", "operation-actions");
  const run = node("button", "action-button", action.mutating ? "Run action" : "Open action");
  run.type = "submit";
  const cancel = node("button", "secondary-button", "Cancel");
  cancel.type = "button";
  cancel.addEventListener("click", () => closeActionSheet());
  actions.append(run, cancel);
  form.append(status, actions);
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!form.reportValidity()) return;
    status.classList.remove("is-error");
    status.textContent = action.mutating ? "Running action…" : "Opening action…";
    run.disabled = true;
    const inputs = [];
    for (const parameter of action.parameters || []) {
      const control = controls.get(parameter);
      const value = control.type === "checkbox" ? String(control.checked) : String(control.value);
      inputs.push(`${parameter}=${value}`);
    }
    try {
      const fields = managedCapabilityFields(descriptor, {
        scope,
        sourceID: source.id,
        operationID: action.id,
        inputs,
      });
      const result = await runManagedCapability(descriptor, { fields, worldID });
      renderWebResult(descriptor, result);
      await refreshWebTargets(descriptor, result);
      status.textContent = result.accepted === false ? "Action was not accepted." : "Action completed.";
    } catch (error) {
      status.textContent = error?.message || webErrorMessage(0);
      status.classList.add("is-error");
    } finally {
      run.disabled = false;
    }
  });
  elements.operationDetail.append(form);
  form.querySelector("input, button")?.focus({ preventScroll: true });
}

async function openManagementView({
  scope,
  source,
  worldID,
  view,
  hostPathRestricted = false,
  trigger,
}) {
  if (managementViewIsCLIOnly(view, hostPathRestricted)) {
    showToast("Configuration and host-path views are available only in the local CLI.");
    return;
  }
  const descriptor = capabilityFor(
    scope === "world" ? NATIVE_ACTION_CANDIDATES.worldObjectView : NATIVE_ACTION_CANDIDATES.objectView,
  );
  if (!descriptor || !isExactID(source?.id)) {
    showToast("This object view is unavailable in the current context.");
    return;
  }
  openManagementDialog({
    title: view.summary || formatKey(view.id),
    summary: `${source.name || "Object"} · structured ${formatKey(view.source || "summary").toLocaleLowerCase()} view`,
    trigger,
  });
  const status = node("p", "inline-status", "Opening view…");
  status.setAttribute("role", "status");
  status.setAttribute("aria-live", "polite");
  elements.operationDetail.append(status);
  try {
    const fields = managedCapabilityFields(descriptor, {
      scope,
      sourceID: source.id,
      operationID: view.id,
    });
    const result = await runManagedCapability(descriptor, { fields, worldID });
    renderWebResult(descriptor, result);
    status.textContent = result.accepted === false ? "View was not available." : "View opened.";
  } catch (error) {
    status.textContent = error?.message || webErrorMessage(0);
    status.classList.add("is-error");
  }
}

function renderPackages(snapshot) {
  const selectedKey = nativeState().domainSelections.packages?.packageKey;
  const available = Array.isArray(snapshot.packages) ? snapshot.packages : [];
  const retained = Array.isArray(snapshot.retainedPackages) ? snapshot.retainedPackages : [];
  const allKeys = Array.from(new Set([
    ...available.map((candidate) => `${candidate.id}@${candidate.version}`),
    ...retained.map((candidate) => `${candidate.id}@${candidate.version}`),
  ]));
  const packageKey = allKeys.includes(selectedKey) ? selectedKey : allKeys[0];
  const availableItem = available.find((candidate) => `${candidate.id}@${candidate.version}` === packageKey) || null;
  const retainedItem = retained.find((candidate) => `${candidate.id}@${candidate.version}` === packageKey) || null;
  const item = availableItem || retainedItem
    ? { ...(availableItem || {}), ...(retainedItem || {}) }
    : null;
  elements.webCapabilityContextActions.append(nativeActionButton("Install package", "plus", NATIVE_ACTION_CANDIDATES.installPackage, {}, { primary: true }));
  if (!item) {
    elements.workspaceContent.append(noContent("No packages", "Packages become available here when their trusted sources are installed.", "package"));
    return;
  }
  const installed = item.isInstalled === true || item.visible === true;
  const packageState = installed ? "Installed" : item.contentHash ? "Retained" : "Available";
  const builtInSource = !item.contentHash && String(item.id || "").startsWith("org.mikrokhoros.")
    ? `builtin:${item.id.slice("org.mikrokhoros.".length)}`
    : "";
  elements.workspaceContent.append(renderDetailHeader({
    title: item.displayName || item.id,
    subtitle: item.summary || "Object package",
    meta: [`${item.id}@${item.version}`, packageState],
    actions: [
      installed
        ? nativeActionButton("Remove", "trash", NATIVE_ACTION_CANDIDATES.removePackage, { packageID: item.id, version: item.version })
        : nativeActionButton("Install", "plus", NATIVE_ACTION_CANDIDATES.installPackage, { source: builtInSource }, { primary: true }),
    ],
  }));
  const overview = node("dl", "native-detail-grid");
  overview.append(
    valueLine("Package", `${item.id}@${item.version}`, { mono: true }),
    valueLine("Runtime", item.runtime || "mikrokhoros object runtime"),
    valueLine("Management", `${item.management?.fieldCount || 0} fields · ${item.management?.actionCount || 0} actions · ${item.management?.viewCount || 0} views`),
    valueLine("Installation", installed ? "Installed" : "Not installed"),
    ...(item.contentHash ? [valueLine("Content hash", item.contentHash, { mono: true })] : []),
    ...(item.installedAt ? [valueLine("Installed", compactDate(item.installedAt))] : []),
    ...(item.visible !== undefined ? [valueLine("Visible", item.visible ? "Yes" : "No")] : []),
    ...(item.sourceCount !== undefined ? [
      valueLine("Active source usage", String(item.sourceCount)),
      valueLine("Retained source usage", String(Math.max(0, Number(item.retainedSourceCount || 0) - Number(item.sourceCount || 0)))),
    ] : []),
  );
  elements.workspaceContent.append(contentSection("Package", overview));
  const capabilities = exactMetadataGrid([
    ["Requested capabilities", item.requestedCapabilityIDs, { empty: "No requested capabilities", label: "capability" }],
  ]);
  elements.workspaceContent.append(contentSection("Capabilities", capabilities));
}

function compactOverflowControl({ label, actions }) {
  const anchor = node("div", "template-overflow-anchor");
  const trigger = node("button", "native-button icon-control template-overflow-trigger");
  trigger.type = "button";
  trigger.setAttribute("aria-label", label);
  trigger.setAttribute("aria-haspopup", "menu");
  trigger.setAttribute("aria-expanded", "false");
  trigger.append(icon("dots-three", "control-icon"));
  const menu = node("div", "floating-menu template-overflow-menu");
  menu.hidden = true;
  menu.setAttribute("role", "menu");
  menu.setAttribute("aria-label", label);
  for (const action of actions) {
    const row = node("button", "menu-row");
    row.type = "button";
    row.setAttribute("role", "menuitem");
    row.append(icon(action.icon || "plus"), node("span", "row-title", action.label), node("span", "menu-meta", ""));
    row.addEventListener("click", () => {
      closeActiveSurface({ restoreFocus: false });
      if (typeof action.onSelect === "function") {
        action.onSelect({ trigger, row });
        return;
      }
      openContextAction(action.candidates, {
        label: action.label,
        prefill: action.prefill || {},
        trigger,
      });
    });
    menu.append(row);
  }
  trigger.addEventListener("click", () => openSurface(trigger, menu));
  menu.addEventListener("keydown", menuKeyboard);
  anchor.append(trigger, menu);
  return anchor;
}

function templateHelpQuery() {
  return "world template";
}

function renderTemplates(snapshot) {
  const key = nativeState().domainSelections.templates?.templateKey;
  const template = snapshot.templates.find((item) => `${item.id}@${item.version}` === key) || snapshot.templates[0];
  if (!template) {
    elements.workspaceContent.append(noContent("No templates", "Trusted template definitions appear here when installed.", "file-text"));
    return;
  }
  const prefill = { templateID: template.id, template: template.id, version: template.version };
  elements.webCapabilityContextActions.append(
    nativeActionButton("Check status in World…", "globe", NATIVE_ACTION_CANDIDATES.templateStatus, prefill),
    nativeActionButton("Apply to World…", "play", NATIVE_ACTION_CANDIDATES.templateApply, prefill, { primary: true }),
    compactOverflowControl({
      label: "More template actions",
      actions: [{
        label: "Create World…",
        icon: "plus",
        candidates: NATIVE_ACTION_CANDIDATES.createWorld,
        prefill,
      }, {
        label: "Template help",
        icon: "info",
        onSelect: () => openHelp({ query: templateHelpQuery() }),
      }],
    }),
  );
  const table = node("div", "template-components-table");
  table.setAttribute("role", "table");
  table.setAttribute("aria-label", `${template.displayName || template.id} object composition`);
  const head = node("div", "template-component-row template-component-head");
  head.setAttribute("role", "row");
  const objectHead = node("span", "", "Object");
  const packageHead = node("span", "", "Package");
  const placementHead = node("span", "", "Placement");
  for (const cell of [objectHead, packageHead, placementHead]) cell.setAttribute("role", "columnheader");
  head.append(objectHead, packageHead, placementHead);
  table.append(head);
  const placements = Array.isArray(template.placements) ? template.placements : [];
  const components = new Map((template.components || []).map((component) => [component.key, component]));
  const rows = placements.length ? placements : (template.components || []).map((component) => ({
    componentKey: component.key,
    kind: "source",
    displayName: component.inventoryName || component.key,
    requestedCoordinate: component.requestedCoordinate,
  }));
  const objectCount = rows.length;
  const componentCount = components.size;
  elements.workspaceContent.append(renderDetailHeader({
    title: template.displayName || template.id,
    subtitle: template.summary || "Trusted host template",
    meta: [
      `${template.id}@${template.version}`,
      `${objectCount} object${objectCount === 1 ? "" : "s"}`,
      template.trusted ? "Trusted" : "Local",
    ],
  }));
  const placementByLocalID = new Map(rows.map((placement) => [
    `${placement.componentKey}:${placement.id || "root"}`,
    placement,
  ]));
  for (const placement of rows) {
    const component = components.get(placement.componentKey);
    const row = node("div", "template-component-row");
    row.setAttribute("role", "row");
    const object = node("span", "template-object-name");
    object.setAttribute("role", "cell");
    object.append(
      icon("cube", "template-object-icon"),
      node("span", "", placement.displayName || component?.inventoryName || placement.componentKey),
    );
    const packageCell = node("code", "", component ? `${component.packageID}@${component.packageVersion}` : "—");
    let parentSpace = "world";
    if (placement.kind === "owned") {
      parentSpace = placement.parentID && placement.parentID !== "root"
        ? placementByLocalID.get(`${placement.componentKey}:${placement.parentID}`)?.displayName || placement.parentID
        : component?.inventoryName || placement.componentKey;
    }
    const coordinate = placement.requestedCoordinate
      ? `(${placement.requestedCoordinate.x}, ${placement.requestedCoordinate.y})`
      : "—";
    const placementCell = node("code", "", `${parentSpace} · ${coordinate}`);
    placementCell.title = `${parentSpace} ${coordinate}`;
    packageCell.setAttribute("role", "cell");
    placementCell.setAttribute("role", "cell");
    row.append(object, packageCell, placementCell);
    table.append(row);
  }
  elements.workspaceContent.append(contentSection("Objects", table));
  const placementNote = node(
    "p",
    "native-detail-copy",
    `This template declares ${componentCount} root component${componentCount === 1 ? "" : "s"} and ${objectCount} placement${objectCount === 1 ? "" : "s"}; applying it creates those declared placements in the chosen World.`,
  );
  elements.workspaceContent.append(placementNote);
}

function renderSettings(snapshot) {
  const selected = nativeState().domainSelections.settings?.setting;
  const section = settingsSections(snapshot).find((item) => item.id === selected) || settingsSections(snapshot)[0];
  if (!section) {
    elements.workspaceContent.append(noContent("No settings", "mikrokhoros Web did not expose any configurable settings.", "gear-six"));
    return;
  }
  if (section.id === "diagnostics") {
    elements.webCapabilityContextActions.append(nativeActionButton("Run diagnostics", "stethoscope", NATIVE_ACTION_CANDIDATES.diagnostics, {}, { primary: true }));
  } else if (section.id === "advanced") {
    elements.webCapabilityContextActions.append(nativeActionButton("Validate settings", "check-circle", NATIVE_ACTION_CANDIDATES.validateSettings, {}, { primary: true }));
  }
  const sectionActions = [];
  if (section.id === "product") {
    sectionActions.push(
      nativeActionButton("Initialize", "plus", NATIVE_ACTION_CANDIDATES.initializeProduct),
      nativeActionButton("Product status", "info", NATIVE_ACTION_CANDIDATES.productStatus),
    );
  }
  if (section.id === "adapters") {
    sectionActions.push(nativeActionButton("Refresh adapters", "circle-notch", NATIVE_ACTION_CANDIDATES.adapters));
  }
  elements.workspaceContent.append(renderDetailHeader({
    title: section.label,
    subtitle: section.id === "product" ? "Local product identity and selected World" : "mikrokhoros Web settings",
    actions: sectionActions,
  }));

  if (section.id === "product") {
    const overview = node("dl", "native-detail-grid");
    overview.append(
      valueLine("State", formatKey(snapshot.status?.state || "ready")),
      valueLine("Current World", snapshot.currentWorld?.name || "No current World"),
      valueLine("Worlds", String(snapshot.counts?.worlds ?? 0)),
      valueLine("Agents", String(snapshot.counts?.agents ?? 0)),
      valueLine("Inventory sources", String(snapshot.counts?.inventorySources ?? 0)),
      valueLine("Packages", String(snapshot.counts?.packages ?? 0)),
      valueLine("Templates", String(snapshot.counts?.templates ?? 0)),
    );
    elements.workspaceContent.append(contentSection("Local product", overview));
    return;
  }

  if (section.id === "diagnostics") {
    const notice = node("div", "native-notice");
    notice.append(
      icon("stethoscope", "native-notice-icon"),
      node("p", "", "Run the product doctor to verify configuration, storage recovery, Inventory, agents, and World state."),
    );
    elements.workspaceContent.append(contentSection("Health check", notice));
    return;
  }

  if (["agents", "runtime", "terminal"].includes(section.id)) {
    elements.workspaceContent.append(contentSection(section.label, renderSettingsValues(section.settings || [])));
    return;
  }

  if (section.id === "adapters") {
    const adapters = node("div", "native-adapter-list");
    for (const adapter of snapshot.adapters || []) {
      const row = node("div", "native-adapter-row");
      row.append(node("span", "", adapter.label));
      row.append(node(
        "span",
        adapter.detected ? "native-status is-ready" : "native-status",
        adapter.detected ? "Available" : adapter.declared ? "Not detected" : "Not configured",
      ));
      adapters.append(row);
    }
    elements.workspaceContent.append(contentSection("Available adapters", adapters.childElementCount ? adapters : noContent("No adapters", "No AI adapter is declared in this local product.", "info")));
    return;
  }

  const advanced = node("div", "settings-action-grid");
  const actions = [
    ["Configuration summary", "info", NATIVE_ACTION_CANDIDATES.showConfiguration],
    ["Configuration keys", "file-text", NATIVE_ACTION_CANDIDATES.configurationKeys],
    ["Read setting", "magnifying-glass", NATIVE_ACTION_CANDIDATES.readSetting],
    ["Configuration selection", "file-text", NATIVE_ACTION_CANDIDATES.configurationSelection],
    ["Validate configuration", "check-circle", NATIVE_ACTION_CANDIDATES.validateSettings],
    ["Reset configuration…", "circle-notch", NATIVE_ACTION_CANDIDATES.resetSetting],
    ["Local host", "globe", NATIVE_ACTION_CANDIDATES.hostStatus],
  ];
  for (const [label, iconName, candidates] of actions) advanced.append(nativeActionButton(label, iconName, candidates));
  elements.workspaceContent.append(contentSection("Advanced tools", advanced));
}

function renderSettingsValues(settings) {
  const values = node("dl", "native-settings-list");
  for (const setting of settings) {
    const row = node("div", "native-setting-row");
    row.append(valueLine(setting.label, setting.value, { mono: false }));
    const settingActions = node("div", "native-interface-actions");
    settingActions.append(
      nativeActionButton("Edit", "pencil-simple", NATIVE_ACTION_CANDIDATES.editSetting, { key: setting.key, setting: setting.key }),
      nativeActionButton("Reset", "circle-notch", NATIVE_ACTION_CANDIDATES.resetSetting, { key: setting.key, setting: setting.key }),
    );
    row.append(settingActions);
    values.append(row);
  }
  return values;
}

function selectDomainEntity(view, selection) {
  if (state.webView === view && state.activeWorkspaceScrollKey) {
    rememberWorkspaceScroll(view, state.activeWorkspaceScrollKey);
  }
  nativeState().domainSelections[view] = { ...nativeState().domainSelections[view], ...selection };
  const routeSelection = {};
  if (view === "agentManager") routeSelection.agent = selection.agent;
  if (view === "inventory") Object.assign(routeSelection, { source: selection.source, folder: selection.folder });
  if (view === "packages") {
    const [packageID, version] = String(selection.packageKey || "").split(/@(?=[^@]+$)/);
    routeSelection.package = packageID || null;
    routeSelection.version = version || null;
  }
  if (view === "templates") routeSelection.template = selection.templateKey;
  if (view === "settings") routeSelection.setting = selection.setting;
  setDomainRoute(routeSelection);
  if (isCompactSidebarViewport()) setSidebarCollapsed(true);
  renderDomainView();
  elements.workspaceContent.querySelector(".native-entity-header, .native-empty-state")?.focus?.({ preventScroll: true });
}

function capabilityFor(candidates) {
  const values = Array.isArray(candidates) ? candidates : [candidates];
  return values
    .map((id) => state.capabilities.find((capability) => capability.id === id && capability.enabled))
    .find(Boolean) || null;
}

function semanticActionLabel(descriptor) {
  return state.activeActionLabel || NATIVE_ACTION_LABELS[descriptor?.id] || "Continue";
}

function prefillActionFields(form, values) {
  if (!values || typeof values !== "object") return;
  const normalized = (value) => String(value || "").replace(/[^a-z0-9]/gi, "").toLocaleLowerCase();
  const aliasValues = new Map(Object.entries(values).map(([key, value]) => [normalized(key), value]));
  for (const control of form.querySelectorAll("[data-field-id]")) {
    const id = normalized(control.dataset.fieldId || control.name);
    const candidates = [id];
    if (/agent/.test(id)) candidates.push("agentid");
    if (/source|inventory/.test(id)) candidates.push("sourceid");
    if (/template/.test(id)) candidates.push("templateid");
    if (/package/.test(id)) candidates.push("packageid");
    if (/version/.test(id)) candidates.push("version");
    if (/folder/.test(id)) candidates.push("folderid");
    if (/object/.test(id)) candidates.push("objectid");
    if (/setting|key/.test(id)) candidates.push("key");
    if (/path.*url|source/.test(id)) candidates.push("source", "pathorurl");
    const matched = candidates.map((candidate) => aliasValues.get(candidate)).find((value) => value !== undefined && value !== null);
    if (matched === undefined) continue;
    if (control.type === "checkbox") control.checked = matched === true || matched === "true";
    else if (control.type !== "file" && control.type !== "password") control.value = String(matched);
    control.dispatchEvent(new Event("change", { bubbles: true }));
  }
}

function openContextAction(candidates, { label = "", prefill = {}, trigger = null, worldLock = null } = {}) {
  if (Array.isArray(candidates) && candidates.includes("__object_interface__")) {
    const section = elements.workspaceContent.querySelector(".native-object-interface");
    section?.scrollIntoView({ behavior: "smooth", block: "start" });
    return;
  }
  const descriptor = capabilityFor(candidates);
  if (!descriptor) {
    showToast("This control is not available in the current local product.");
    announce("This control is not available in the current local product.");
    return;
  }
  cancelWebActivity();
  state.controllerTranscript = [];
  state.selectedOperationID = descriptor.id;
  state.activeActionLabel = label || NATIVE_ACTION_LABELS[descriptor.id] || "Continue";
  state.actionWorldLock = isExactID(worldLock) ? worldLock : null;
  state.actionReturnFocus = trigger || (document.activeElement instanceof HTMLElement ? document.activeElement : null);
  elements.actionBackdrop.hidden = false;
  renderOperation(descriptor);
  const form = elements.operationDetail.querySelector("form");
  if (form) prefillActionFields(form, prefill);
  elements.actionDialog.focus({ preventScroll: true });
}

function closeActionSheet({ restoreFocus = true } = {}) {
  if (!elements.actionBackdrop || elements.actionBackdrop.hidden) return;
  cancelWebActivity();
  clearSensitiveFields();
  elements.actionBackdrop.hidden = true;
  clearNode(elements.operationDetail);
  elements.operationDetail.hidden = true;
  const returnFocus = state.actionReturnFocus;
  state.actionReturnFocus = null;
  state.activeActionLabel = null;
  state.actionWorldLock = null;
  if (restoreFocus && returnFocus?.isConnected) returnFocus.focus({ preventScroll: true });
}

function renderOperation(descriptor) {
  elements.operationDetail.hidden = false;
  elements.operationDetail.tabIndex = -1;
  clearNode(elements.operationDetail);
  state.privateRevealed = false;
  const heading = node("header", "operation-heading");
  const copy = node("div");
  copy.append(node("h2", "", semanticActionLabel(descriptor)));
  if (descriptor.summary) copy.append(node("p", "", descriptor.summary));
  heading.append(copy);
  elements.operationDetail.append(heading);
  if (descriptor.mode === "privateViewer" || descriptor.mode === "download") {
    const notice = node("section", "prepared-panel private-data-warning");
    notice.append(node("h3", "", "Private local data"), node("p", "", "Review and save this local information only where you intend to protect it."));
    elements.operationDetail.append(notice);
  }
  const form = node("form", "operation-form");
  form.noValidate = true;
  form.dataset.operationId = descriptor.id;
  appendWorldField(form, descriptor);
  for (const field of descriptor.fields) appendGeneratedField(form, descriptor, field);
  const status = node("p", "inline-status");
  status.setAttribute("role", "status");
  status.setAttribute("aria-live", "polite");
  const actions = node("div", "operation-actions");
  const primary = node("button", "action-button", descriptor.mode === "confirmation" ? "Review" : "Continue");
  primary.type = "submit";
  actions.append(primary);
  const cancel = node("button", "secondary-button", "Cancel");
  cancel.type = "button";
  cancel.addEventListener("click", () => closeActionSheet());
  actions.append(cancel);
  form.append(status, actions);
  form.addEventListener("submit", (event) => submitWebOperation(event, descriptor));
  elements.operationDetail.append(form);
}

function renderPreparedConfirmation(form, descriptor, plan, status) {
  form.querySelector(".prepared-panel")?.remove();
  if (!plan || typeof plan.planID !== "string" || plan.operationID !== descriptor.id) throw new Error("The prepared action response was invalid. Refresh and try again.");
  const panel = node("section", "prepared-panel");
  panel.append(node("h3", "", "Review changes"), node("p", "", typeof plan.summary === "string" ? plan.summary : "Review this action before confirming it."));
  if (typeof plan.expiresAt === "string") panel.append(node("p", "field-hint", `This review expires ${plan.expiresAt}.`));
  const actions = node("div", "operation-actions");
  const confirm = node("button", "action-button", "Confirm");
  confirm.type = "button";
  const cancel = node("button", "secondary-button", "Cancel");
  cancel.type = "button";
  cancel.addEventListener("click", () => { panel.remove(); status.textContent = "Review cancelled."; });
  confirm.addEventListener("click", async () => {
    confirm.disabled = true;
    cancel.disabled = true;
    status.textContent = "Applying…";
    try {
      const controller = new AbortController();
      state.webRequest = controller;
      const result = await fetchWebCapability("/api/v1/web/commit", { planID: plan.planID, confirmed: true }, controller.signal);
      state.webRequest = null;
      panel.remove();
      if (result.download) beginDownload(result);
      else renderWebResult(descriptor, result);
      await refreshWebTargets(descriptor, result);
      status.textContent = "Changes applied.";
    } catch (error) {
      if (error?.name !== "AbortError") {
        status.textContent = error?.message || webErrorMessage(0);
        status.classList.add("is-error");
      }
      confirm.disabled = false;
      cancel.disabled = false;
    }
  });
  actions.append(confirm, cancel);
  panel.append(actions);
  form.append(panel);
  status.textContent = "Review the changes before confirming.";
  confirm.focus();
}

function renderWebResult(descriptor, result, { secret = "" } = {}) {
  elements.operationDetail.querySelector(".result-viewer")?.remove();
  const viewer = node("section", "result-viewer");
  const accepted = result?.accepted !== false;
  viewer.append(node("h3", "", accepted ? "Completed" : "Not completed"));
  const append = (label, value, className = "") => {
    if (typeof value !== "string" || !value) return;
    const safe = secret ? value.split(secret).join("[redacted]") : value;
    const block = node("div", "result-block");
    block.append(node("span", "result-block-label", label), node("pre", `result-code ${className}`.trim(), safe));
    viewer.append(block);
  };
  append("Output", result?.standardOutput);
  append("Details", result?.standardError, "result-error");
  if (viewer.children.length > 1) elements.operationDetail.append(viewer);
}

async function refreshWebTargets(descriptor, result) {
  if (result?.accepted === false) return;
  const targets = new Set((Array.isArray(result?.refreshTargets) ? result.refreshTargets : descriptor.refreshTargets || []).filter(Boolean));
  const nativeView = state.webView;
  if (DOMAIN_ENDPOINTS[nativeView]) await loadDomainSnapshot(nativeView, { quiet: true });
  if (targets.has("world")) {
    const route = state.webView === "world" ? currentRoute() : state.lastWorldRoute || {};
    await loadWorld({ route, mode: "preserve-camera", quiet: true, suppressUnavailable: true, synchronizeRoute: state.webView === "world" });
  }
}

async function loadCapabilities({ preserveSelection = true } = {}) {
  state.capabilitiesError = null;
  try {
    const response = await window.fetch("/api/v1/web/capabilities", { method: "GET", credentials: "same-origin", headers: { Accept: "application/json" } });
    if (response.status === 401 || response.status === 403) {
      const error = new Error("session");
      error.code = "session";
      throw error;
    }
    if (!response.ok) throw new Error("request");
    const payload = await response.json();
    if (!payload || !Array.isArray(payload.capabilities)) throw new Error("contract");
    const unique = new Map();
    for (const raw of payload.capabilities) {
      const capability = normalizedCapability(raw);
      if (capability && !unique.has(capability.id)) unique.set(capability.id, capability);
    }
    state.capabilities = Array.from(unique.values());
    state.capabilitiesLoaded = true;
    if (!preserveSelection && state.webView === "world") state.selectedOperationID = null;
  } catch (error) {
    state.capabilitiesLoaded = true;
    state.capabilitiesError = error?.code === "session" ? "session" : "unavailable";
    state.capabilities = [];
  }
  renderHelpResults();
}

function switchWebView(view, { historyMode = "push", focusMain = false } = {}) {
  if (!ROUTABLE_WEB_VIEWS.includes(view)) view = "world";
  nativeState();
  const previousView = state.webView;
  if (previousView !== "world" && previousView !== view && state.activeWorkspaceScrollKey) {
    rememberWorkspaceScroll(previousView, state.activeWorkspaceScrollKey);
  }
  if (state.webView === "world" && view !== "world") rememberWorldRoute();
  closeActiveSurface({ restoreFocus: false });
  closeHelp({ restoreFocus: false });
  closeActionSheet({ restoreFocus: false });
  cancelWebActivity();
  clearSensitiveFields();
  state.webView = view;
  const isWorld = view === "world";
  elements.worldMain.hidden = !isWorld;
  elements.workspaceMain.hidden = isWorld;
  elements.worldContextPicker.hidden = !isWorld;
  elements.sidebarScroll.hidden = !isWorld;
  elements.domainSidebar.hidden = isWorld;
  if (isCompactSidebarViewport()) setSidebarCollapsed(true);
  const meta = WEB_VIEW_META[view] || WEB_VIEW_META.world;
  const appTriggerLabel = elements.appViewTrigger.querySelector(".control-label");
  const appTriggerIcon = elements.appViewTrigger.querySelector(".control-icon");
  appTriggerLabel.textContent = meta.label;
  appTriggerIcon.src = `/icons/phosphor/${meta.icon}.svg`;
  elements.appViewTrigger.setAttribute("aria-label", `Choose mikrokhoros Web view. Current view: ${meta.label}`);
  document.title = `mikrokhoros · ${meta.label}`;
  for (const row of elements.appViewMenu.querySelectorAll("[data-app-view]")) {
    const selected = row.dataset.appView === view;
    row.classList.toggle("is-selected", selected);
    row.setAttribute("aria-checked", selected ? "true" : "false");
    row.querySelector(".menu-check")?.toggleAttribute("hidden", !selected);
  }
  elements.settingsButton.setAttribute("aria-current", view === "settings" ? "page" : "false");
  if (historyMode) {
    if (isWorld) {
      const remembered = state.lastWorldRoute || {};
      updateRoute({ world: remembered.world, container: remembered.container }, historyMode);
    } else {
      const current = currentRoute();
      const nextRoute = current.view === view
        ? { ...current, view }
        : { view };
      updateRoute(nextRoute, historyMode);
    }
  }
  if (isWorld) {
    state.selectedOperationID = null;
    window.setTimeout(renderWorld, 0);
    return;
  }
  const snapshot = domainSnapshotFor(view);
  nativeState().domainSelections[view] = domainSelectionFromRoute(view, snapshot);
  renderDomainView();
  loadDomainSnapshot(view, { quiet: true });
  if (focusMain) elements.workspaceContent.focus?.({ preventScroll: true });
}

function openWorldActions(operationID = null) {
  const descriptor = operationID ? capabilityFor([operationID]) : null;
  if (descriptor) {
    openContextAction([descriptor.id], { label: NATIVE_ACTION_LABELS[descriptor.id] || "Continue" });
    return;
  }
  const worldID = state.snapshot?.selectedWorldID;
  if (!isExactID(worldID)) {
    showToast("Choose a World first.");
    return;
  }
  openManagementDialog({
    title: "World details",
    summary: "Manage the exact selected World. Each action keeps its own review and privacy boundary.",
    trigger: elements.viewTrigger,
  });
  const list = node("div", "management-contract-list world-details-actions");
  const actions = [
    ["Make current", "globe", "worldUse"],
    ["Rename", "pencil-simple", "worldRename"],
    ["Inspect private state", "info", "worldInspect"],
    ["Export private journal", "arrow-square-out", "worldExport"],
    ["Delete", "trash", "worldDelete"],
  ];
  for (const [label, iconName, capabilityID] of actions) {
    const button = node("button", "management-contract-card world-detail-action");
    button.type = "button";
    button.append(icon(iconName, "control-icon"), node("span", "", label));
    button.addEventListener("click", () => openContextAction(
      [capabilityID],
      { label, prefill: { worldID }, trigger: button },
    ));
    list.append(button);
  }
  elements.operationDetail.append(list);
}

function renderHelpResults() {
  if (!elements.helpResults) return;
  const query = elements.helpSearch.value.trim().toLocaleLowerCase();
  const topics = [
    { title: "Open help", summary: "Open this searchable reference from anywhere outside an editing field.", command: "/" },
    { title: "Close an overlay", summary: "Close Help, menus, dialogs, inspectors, and contextual actions.", command: "Escape" },
    { title: "World view", summary: "Pan with drag or arrow keys; zoom with + and −; press 0 to recenter.", command: "Arrow keys · + · − · 0" },
    ...state.capabilities.map((descriptor) => ({
      title: NATIVE_ACTION_LABELS[descriptor.id] || descriptor.command || formatKey(descriptor.id),
      summary: descriptor.summary || descriptor.fields.map((field) => field.help).filter(Boolean).join(" "),
      command: descriptor.command,
      descriptor,
    })),
  ].filter((topic) => {
    const fields = topic.descriptor?.fields.map((field) => `${field.label} ${field.help} ${field.syntax}`).join(" ") || "";
    return !query || `${topic.title} ${topic.summary} ${topic.command} ${fields}`.toLocaleLowerCase().includes(query);
  });
  clearNode(elements.helpResults);
  for (const topic of topics) {
    const actionable = Boolean(topic.descriptor?.enabled);
    const item = node(actionable ? "button" : "article", "help-topic");
    if (actionable) {
      item.type = "button";
      item.addEventListener("click", () => {
        closeHelp({ restoreFocus: false });
        if (topic.descriptor.view !== "world" && topic.descriptor.view !== "help") switchWebView(topic.descriptor.view);
        openContextAction([topic.descriptor.id], { label: NATIVE_ACTION_LABELS[topic.descriptor.id] || "Continue", trigger: elements.appViewTrigger });
      });
    }
    item.append(node("h2", "", topic.title));
    if (topic.summary) item.append(node("p", "", topic.summary));
    if (topic.descriptor && !topic.descriptor.enabled) {
      item.append(node("span", "native-chip", "CLI only"));
    }
    if (topic.command) item.append(node("code", "", topic.command));
    elements.helpResults.append(item);
  }
  elements.helpEmpty.hidden = Boolean(topics.length);
}

function setupInteractions() {
  setupBaseInteractions();
  elements.domainSearch.addEventListener("input", renderDomainView);
  elements.actionDialogClose.addEventListener("click", () => closeActionSheet());
  elements.actionBackdrop.addEventListener("pointerdown", (event) => {
    if (event.target === elements.actionBackdrop) closeActionSheet();
  });
  elements.workspaceRefresh.addEventListener("click", async () => {
    if (!DOMAIN_ENDPOINTS[state.webView]) return;
    elements.workspaceRefresh.disabled = true;
    await Promise.all([loadCapabilities(), loadDomainSnapshot(state.webView)]);
    elements.workspaceRefresh.disabled = false;
  });
  document.addEventListener("keydown", (event) => {
    if (elements.actionBackdrop.hidden) return;
    if (event.key === "Tab") {
      trapModalFocus(event, elements.actionDialog);
      return;
    }
    if (event.key === "Escape") {
      event.preventDefault();
      event.stopImmediatePropagation();
      closeActionSheet();
    }
  }, true);
}
