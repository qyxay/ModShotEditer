'use strict';
/* ============================================================
 * OneShot 可视化地图编辑器 - 前端逻辑
 * 瓦片映射(按 ModShot 引擎 tilemap.cpp):
 *   id >= 384 : tsInd = id-384, 8列网格: x=(tsInd%8)*32, y=floor(tsInd/8)*32
 *   id <  384 : autotile, 槽位=floor((id-1)/48), 变体=(id-1)%48
 * ============================================================ */

const $ = s => document.querySelector(s);
const TS = 32;                    // 瓦片像素
const AUTOTILE_OFFSET = 48 * 8;   // 384

const state = {
  maps: [],
  cur: null,          // 当前地图 JSON
  ts: null,           // tileset JSON
  tsImg: null,        // tileset Image
  atImgs: {},         // autotile name -> Image
  selectedTile: 0,    // 当前画笔瓦片 id (0=空)
  selEvent: null,     // 当前选中事件
  drag: null,         // 拖拽状态
  hover: null,        // 鼠标悬停格 {x,y} (放置预览)
  undoStack: [],      // 撤销快照
  selIds: new Set(),  // 面板选中瓦片 id 集合
  selGrid: null,      // 多选时画笔网格 {tiles, rows, cols}
  panelDrag: null,    // 面板框选拖拽状态
  in_mod: false,
  dirty: false,
};

/* ---------- 撤销 ---------- */
const UNDO_MAX = 30;
function snapshot() {
  state.undoStack.push(JSON.stringify({ layers: state.cur.layers, events: state.cur.events }));
  if (state.undoStack.length > UNDO_MAX) state.undoStack.shift();
}
function undo() {
  if (!state.undoStack.length) { setStatus('无可撤销'); return; }
  const snap = JSON.parse(state.undoStack.pop());
  state.cur.layers = snap.layers;
  state.cur.events = snap.events;
  state.selEvent = null;
  buildEventPanel();
  render();
  markDirty();
  setStatus(`已撤销 (剩余 ${state.undoStack.length})`);
}

/* ---------- 工具 ---------- */
function setStatus(msg) { $('#status').textContent = msg; }

async function api(url, opts) {
  const r = await fetch(url, opts);
  if (!r.ok) throw new Error(await r.text());
  return r.json();
}

/* ---------- 瓦片映射 ---------- */
function tileRect(id) {
  if (!id) return null;
  if (id < AUTOTILE_OFFSET) return { at: true, tileId: id };
  const ts = id - AUTOTILE_OFFSET;
  return { at: false, sx: (ts % 8) * TS, sy: Math.floor(ts / 8) * TS, sw: TS, sh: TS };
}
function autotileSlot(id) { return Math.floor((id - 1) / 48); }

/* ---------- 面板多选 ---------- */
function tsRC(id) { const t = id - AUTOTILE_OFFSET; return { r: Math.floor(t / 8), c: t % 8 }; }
function tsId(r, c) { return AUTOTILE_OFFSET + r * 8 + c; }

/* 从选中集合构建画笔网格 (bounding box, 空洞填第一个) */
function buildSelGrid(ids) {
  if (!ids.size) { state.selGrid = null; return; }
  let minR = 1e9, maxR = -1, minC = 1e9, maxC = -1, first = null;
  ids.forEach(id => {
    const { r, c } = tsRC(id);
    if (r < minR) minR = r; if (r > maxR) maxR = r;
    if (c < minC) minC = c; if (c > maxC) maxC = c;
    if (first === null) first = id;
  });
  const rows = maxR - minR + 1, cols = maxC - minC + 1, tiles = [];
  for (let r = 0; r < rows; r++)
    for (let c = 0; c < cols; c++) {
      const id = tsId(minR + r, minC + c);
      tiles.push(ids.has(id) ? id : first);
    }
  state.selGrid = { tiles, rows, cols };
}

/* 根据 selIds 高亮面板瓦片 */
function updateTileHighlight() {
  document.querySelectorAll('.at-tile,.ts-tile').forEach(n => {
    n.classList.toggle('selected', state.selIds.has(Number(n.dataset.tileId)));
  });
}

/* 单选一个图块 */
function selectTile(id, silent) {
  state.selectedTile = id;
  state.selIds = new Set([id]);
  state.selGrid = null;
  updateTileHighlight();
  if (!silent) {
    const { r, c } = tsRC(id);
    setStatus(`选中图块 id=${id} (tsInd=${id - AUTOTILE_OFFSET}, 行${r}列${c})`);
  }
}

/* 单选一个 autotile */
function selectAutotile(slot, name) {
  const id = slot * 48 + 1;
  state.selectedTile = id;
  state.selIds = new Set([id]);
  state.selGrid = null;
  updateTileHighlight();
  setStatus(`选中 autotile #${slot + 1} (${name}), 瓦片id=${id}`);
}

/* 面板框选虚线 (直接用格子坐标定位, 与瓦片对齐) */
function drawPanelSel(tsRoot, d) {
  clearPanelSel(tsRoot);
  const x = Math.min(d.c0, d.c1) * TS, y = Math.min(d.r0, d.r1) * TS;
  const w = (Math.abs(d.c1 - d.c0) + 1) * TS, h = (Math.abs(d.r1 - d.r0) + 1) * TS;
  const el = document.createElement('div');
  el.id = 'panelSelBox';
  el.style.cssText = `position:absolute;left:${x}px;top:${y}px;width:${w}px;height:${h}px;border:1px solid #0ff;background:rgba(0,255,255,.12);pointer-events:none;z-index:5;`;
  tsRoot.appendChild(el);
}
function clearPanelSel(tsRoot) {
  const el = document.getElementById('panelSelBox');
  if (el) el.remove();
}

/* 从 autotile 图取代表瓦片 (简化: 第一帧左上 32x32) */
function drawAutotile(ctx, name, dx, dy, dsize) {
  const img = state.atImgs[name];
  if (!img) return;
  ctx.drawImage(img, 0, 0, 32, 32, dx, dy, dsize, dsize);
}

/* ---------- 渲染 ---------- */
function render() {
  const c = $('#mapCanvas');
  if (!state.cur) { c.width = 0; c.height = 0; return; }
  const scale = parseFloat($('#zoom').value);
  const W = state.cur.width, H = state.cur.height;
  c.width = W * TS * scale;
  c.height = H * TS * scale;
  const ctx = c.getContext('2d');
  ctx.imageSmoothingEnabled = false;
  ctx.fillStyle = '#101010';
  ctx.fillRect(0, 0, c.width, c.height);

  // 3 层: 底 -> 中 -> 顶
  for (let l = 0; l < state.cur.layers.length; l++) {
    const layer = state.cur.layers[l];
    for (let y = 0; y < H; y++) {
      for (let x = 0; x < W; x++) {
        const id = layer[y][x];
        if (!id) continue;
        const r = tileRect(id);
        if (!r) continue;
        if (r.at) {
          const slot = autotileSlot(id);
          const name = state.ts.autotile_names[slot];
          if (name) drawAutotile(ctx, name, x * TS * scale, y * TS * scale, TS * scale);
        } else {
          ctx.drawImage(state.tsImg, r.sx, r.sy, r.sw, r.sh,
                        x * TS * scale, y * TS * scale, TS * scale, TS * scale);
        }
      }
    }
  }

  // 事件标记
  (state.cur.events || []).forEach(ev => {
    const dx = ev.x * TS * scale, dy = ev.y * TS * scale;
    ctx.fillStyle = 'rgba(255,255,0,.35)';
    ctx.fillRect(dx, dy, TS * scale, TS * scale);
    ctx.strokeStyle = ev.id === (state.selEvent && state.selEvent.id) ? '#fff' : '#ff0';
    ctx.strokeRect(dx + 1, dy + 1, TS * scale - 2, TS * scale - 2);
    if (scale >= 0.6) {
      ctx.fillStyle = 'rgba(0,0,0,.7)';
      ctx.font = `${Math.max(8, 10 * scale)}px sans-serif`;
      ctx.fillText(ev.id, dx + 2, dy + (10 * scale));
    }
  });

  // 网格
  if ($('#gridChk').checked) {
    ctx.strokeStyle = 'rgba(255,255,255,.12)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    for (let x = 1; x < W; x++) { ctx.moveTo(x * TS * scale, 0); ctx.lineTo(x * TS * scale, H * TS * scale); }
    for (let y = 1; y < H; y++) { ctx.moveTo(0, y * TS * scale); ctx.lineTo(W * TS * scale, y * TS * scale); }
    ctx.stroke();
  }

  // 矩形预览
  if (state.drag && state.drag.type === 'rect' && state.drag.x1 != null) {
    const x0 = Math.min(state.drag.x0, state.drag.x1), y0 = Math.min(state.drag.y0, state.drag.y1);
    const x1 = Math.max(state.drag.x0, state.drag.x1), y1 = Math.max(state.drag.y0, state.drag.y1);
    ctx.strokeStyle = state.selectedTile ? '#0ff' : '#f66';
    ctx.lineWidth = 2 / scale;
    ctx.strokeRect(x0 * TS * scale, y0 * TS * scale,
                   (x1 - x0 + 1) * TS * scale, (y1 - y0 + 1) * TS * scale);
  }

  // 瓦片放置预览 (悬停)
  if (!state.drag && state.hover) {
    const hx = state.hover.x, hy = state.hover.y;
    if (hx >= 0 && hy >= 0 && hx < W && hy < H) {
      const tool = $('#toolSel').value;
      if ((tool === 'paint' || tool === 'fill' || tool === 'rect') && (state.selectedTile || state.selGrid)) {
        ctx.globalAlpha = 0.45;
        if (state.selGrid) {
          const g = state.selGrid;
          for (let r = 0; r < g.rows; r++)
            for (let c = 0; c < g.cols; c++) {
              const id = g.tiles[r * g.cols + c];
              const px = (hx + c) * TS * scale, py = (hy + r) * TS * scale;
              if (px < 0 || py < 0 || px >= c.width || py >= c.height) continue;
              const rr = tileRect(id);
              if (rr && rr.at) {
                const name = state.ts.autotile_names[autotileSlot(id)];
                if (name) drawAutotile(ctx, name, px, py, TS * scale);
              } else if (rr && state.tsImg) {
                ctx.drawImage(state.tsImg, rr.sx, rr.sy, rr.sw, rr.sh, px, py, TS * scale, TS * scale);
              }
            }
        } else {
          const r = tileRect(state.selectedTile);
          if (r && r.at) {
            const name = state.ts.autotile_names[autotileSlot(state.selectedTile)];
            if (name) drawAutotile(ctx, name, hx * TS * scale, hy * TS * scale, TS * scale);
          } else if (r && state.tsImg) {
            ctx.drawImage(state.tsImg, r.sx, r.sy, r.sw, r.sh,
                          hx * TS * scale, hy * TS * scale, TS * scale, TS * scale);
          }
        }
        ctx.globalAlpha = 1;
        if (state.selGrid) {
          const g = state.selGrid;
          ctx.strokeStyle = '#0ff';
          ctx.lineWidth = 1 / scale;
          ctx.strokeRect(hx * TS * scale, hy * TS * scale,
                         g.cols * TS * scale, g.rows * TS * scale);
        } else {
          ctx.strokeStyle = '#0ff';
          ctx.lineWidth = 1 / scale;
          ctx.strokeRect(hx * TS * scale, hy * TS * scale, TS * scale, TS * scale);
        }
      } else if (tool === 'erase') {
        ctx.strokeStyle = '#f66';
        ctx.lineWidth = 1 / scale;
        ctx.strokeRect(hx * TS * scale, hy * TS * scale, TS * scale, TS * scale);
      }
    }
  }
}

function canvasPos(e) {
  const c = $('#mapCanvas');
  const r = c.getBoundingClientRect();
  const scale = parseFloat($('#zoom').value);
  const mx = (e.clientX - r.left) / scale, my = (e.clientY - r.top) / scale;
  return { x: Math.floor(mx / TS), y: Math.floor(my / TS) };
}

/* ---------- 瓦片选择面板 ---------- */
function buildTilePanel() {
  const atP = $('#atPanel'), tsP = $('#tsPanel');
  atP.innerHTML = ''; tsP.innerHTML = '';

  // autotile
  state.ts.autotile_names.forEach((name, slot) => {
    if (!name) return;
    const img = state.atImgs[name];
    if (!img) return;
    const div = document.createElement('div');
    div.className = 'at-tile';
    div.dataset.tileId = slot * 48 + 1;
    div.title = `${name} (autotile ${slot + 1}, id ${slot * 48 + 1}-${slot * 48 + 48})`;
    const cv = document.createElement('canvas');
    cv.width = 96; cv.height = 64;
    const ctx = cv.getContext('2d');
    ctx.drawImage(img, 0, 0);
    div.appendChild(cv);
    div.addEventListener('click', () => { selectAutotile(slot, name); });
    atP.appendChild(div);
  });
  if (!atP.children.length) atP.innerHTML = '<div style="color:#888">(无 autotile)</div>';

  // tileset 图块 (8 列网格)
  if (!state.tsImg) { tsP.innerHTML = '<div style="color:#888">(无 tileset 图)</div>'; return; }
  const nCols = 8;
  const nRows = Math.ceil(state.tsImg.naturalHeight / TS);
  const cvs = document.createElement('canvas');
  cvs.width = nCols * TS; cvs.height = nRows * TS;
  const ctx = cvs.getContext('2d');
  ctx.imageSmoothingEnabled = false;
  ctx.drawImage(state.tsImg, 0, 0);
  tsP.appendChild(cvs);
  tsP.style.position = 'relative';
  for (let r = 0; r < nRows; r++) {
    for (let col = 0; col < nCols; col++) {
      const id = AUTOTILE_OFFSET + r * 8 + col;
      const td = document.createElement('div');
      td.className = 'ts-tile';
      td.dataset.tileId = id;
      td.style.cssText = `position:absolute;left:${col * TS}px;top:${r * TS}px;width:${TS}px;height:${TS}px;`;
      tsP.appendChild(td);
    }
  }
  // 面板交互: 单击=单选, Ctrl+单击=连选, 拖拽=框选 (只记录起止瓦片格子 r0c0->r1c1)
  tsP.addEventListener('mousedown', e => {
    const rect = cvs.getBoundingClientRect();
    const c0 = Math.floor((e.clientX - rect.left) / TS);
    const r0 = Math.floor((e.clientY - rect.top) / TS);
    if (r0 < 0 || c0 < 0 || r0 >= nRows || c0 >= nCols) return;
    e.preventDefault();
    state.panelDrag = { r0, c0, r1: r0, c1: c0, ctrl: e.ctrlKey };
    drawPanelSel(tsP, state.panelDrag);
  });
  window.addEventListener('mousemove', e => {
    if (!state.panelDrag) return;
    const rect = cvs.getBoundingClientRect();
    state.panelDrag.r1 = Math.floor((e.clientY - rect.top) / TS);
    state.panelDrag.c1 = Math.floor((e.clientX - rect.left) / TS);
    drawPanelSel(tsP, state.panelDrag);
  });
  window.addEventListener('mouseup', () => {
    if (!state.panelDrag) return;
    const d = state.panelDrag;
    clearPanelSel(tsP);
    const moved = d.r1 !== d.r0 || d.c1 !== d.c0;
    if (!moved) {
      if (d.ctrl) {
        const id = tsId(d.r0, d.c0);
        if (state.selIds.has(id)) { state.selIds.delete(id); }
        else { state.selIds.add(id); }
        state.selectedTile = state.selIds.size ? [...state.selIds][0] : 0;
        buildSelGrid(state.selIds);
        updateTileHighlight();
        setStatus(state.selIds.size > 1 ? `已连选 ${state.selIds.size} 个瓦片, 画笔=整块 ${state.selGrid.rows}x${state.selGrid.cols}` : `选中瓦片 id=${id}`);
      } else {
        selectTile(tsId(d.r0, d.c0));
      }
    } else {
      const set = new Set();
      const ar = Math.max(0, Math.min(d.r0, d.r1)), br = Math.min(nRows - 1, Math.max(d.r0, d.r1));
      const ac = Math.max(0, Math.min(d.c0, d.c1)), bc = Math.min(nCols - 1, Math.max(d.c0, d.c1));
      for (let r = ar; r <= br; r++)
        for (let c = ac; c <= bc; c++)
          set.add(tsId(r, c));
      state.selIds = set;
      state.selectedTile = [...set][0];
      buildSelGrid(set);
      updateTileHighlight();
      setStatus(`框选 ${set.size} 个瓦片 (${state.selGrid.rows}x${state.selGrid.cols} 画笔)`);
    }
    state.panelDrag = null;
  });
}

/* ---------- 事件面板 ---------- */
function buildEventPanel() {
  const list = $('#evList');
  list.innerHTML = '';
  (state.cur.events || []).slice().sort((a, b) => a.id - b.id).forEach(ev => {
    const li = document.createElement('li');
    li.textContent = `#${ev.id} ${ev.name} (${ev.x},${ev.y})`;
    li.dataset.id = ev.id;
    li.addEventListener('click', () => selectEvent(ev.id));
    list.appendChild(li);
  });
  showEventDetail(state.selEvent);
}

function selectEvent(id) {
  state.selEvent = (state.cur.events || []).find(e => e.id === id) || null;
  document.querySelectorAll('#evList li').forEach(li =>
    li.classList.toggle('selected', Number(li.dataset.id) === id));
  showEventDetail(state.selEvent);
  render();
}

function cmdText(cmd) {
  const code = cmd[0];
  switch (code) {
    case 101: return '【对话】' + (cmd[2][0] || '');
    case 401: return '    ' + (cmd[2][0] || '');
    case 355: case 655: return '【脚本】' + (cmd[2][0] || '');
    case 121: return `【开关】${cmd[2][0]}-${cmd[2][1]} = ${cmd[2][2] ? 'ON' : 'OFF'}`;
    case 122: return `【变量】${cmd[2][0]}-${cmd[2][1]}`;
    case 201: return `【转场】${cmd[2].join(',')}`;
    case 101 + 200: return ''; // placeholder
    default: return `【命令 ${code}】${JSON.stringify(cmd[2] || [])}`;
  }
}

function showEventDetail(ev) {
  const d = $('#evDetail');
  if (!ev) { d.innerHTML = '<div style="color:#888">未选择事件</div>'; return; }
  const p0 = ev.pages[0] || {};
  const cmds = (p0.commands || []).map(cmdText).join('\n');
  d.innerHTML = `
    <label>ID: <input type="number" value="${ev.id}" disabled></label>
    <label>名字: <input type="text" id="evName" value="${escAttr(ev.name)}"></label>
    <label>X: <input type="number" id="evX" value="${ev.x}"></label>
    <label>Y: <input type="number" id="evY" value="${ev.y}"></label>
    <label>第1页命令 (只读预览):
      <textarea readonly>${escAttr(cmds)}</textarea></label>
    <button id="evApply">应用修改</button>
    <button id="evDel" style="background:#7d2d2d">删除事件</button>
    <button id="evAdd" style="background:#2d5a7d">＋新事件</button>`;
  $('#evName').addEventListener('change', e => { snapshot(); ev.name = e.target.value; markDirty(); });
  $('#evX').addEventListener('change', e => { snapshot(); ev.x = +e.target.value; render(); markDirty(); });
  $('#evY').addEventListener('change', e => { snapshot(); ev.y = +e.target.value; render(); markDirty(); });
  $('#evApply').addEventListener('click', () => { render(); buildEventPanel(); setStatus('事件已更新'); });
  $('#evDel').addEventListener('click', () => {
    snapshot();
    state.cur.events = state.cur.events.filter(e => e.id !== ev.id);
    state.selEvent = null; buildEventPanel(); render(); markDirty(); setStatus(`已删除事件 #${ev.id}`);
  });
  $('#evAdd').addEventListener('click', () => {
    snapshot();
    const nid = Math.max(0, ...state.cur.events.map(e => e.id)) + 1;
    state.cur.events.push({ id: nid, name: 'EV' + nid, x: 0, y: 0,
      pages: [{ condition: { sw1: null, sw2: null, var: null, self: null },
                graphic: { tile_id: 0, char: '', dir: 2, pattern: 0, hue: 0, opacity: 255, blend: 0 },
                trigger: 0, move_type: 0, move_speed: 3, move_frequency: 3, commands: [] }] });
    buildEventPanel(); selectEvent(nid); render(); markDirty(); setStatus(`已添加事件 #${nid}，可在右侧改名/坐标`);
  });
}
function escAttr(s) { return String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;'); }

/* ---------- 加载 ---------- */
async function loadMap(id) {
  setStatus('加载中...');
  const j = await api(`/api/map/${id}`);
  state.cur = j;
  state.selEvent = null;
  state.dirty = false;
  state.undoStack = [];   // 新地图清空撤销栈
  state.selIds = new Set();
  state.selGrid = null;
  state.selectedTile = 0;

  // tileset
  state.ts = await api(`/api/tileset/${j.tileset_id}`);
  state.tsImg = await loadImg(`/img/tileset/${encodeURIComponent(state.ts.tileset_name)}`).catch(() => null);
  state.atImgs = {};
  for (const name of state.ts.autotile_names) {
    if (name) state.atImgs[name] = await loadImg(`/img/autotile/${encodeURIComponent(name)}`).catch(() => null);
  }
  buildTilePanel();
  buildEventPanel();
  buildInfo();
  render();
  setStatus(`已加载地图 ${j.name} (${j.width}x${j.height}, tileset ${j.tileset_id})${j.in_mod ? ' [mod覆盖]' : ''}`);
}
function loadImg(src) {
  return new Promise((res, rej) => {
    const img = new Image();
    img.onload = () => res(img);
    img.onerror = () => rej(new Error('img fail ' + src));
    img.src = src;
  });
}
function buildInfo() {
  const j = state.cur;
  const t = state.ts;
  $('#mapInfo').innerHTML = `<table>
    <tr><th>ID</th><td>${j.id}</td></tr>
    <tr><th>名字</th><td>${escAttr(j.name)}</td></tr>
    <tr><th>尺寸</th><td>${j.width} x ${j.height}</td></tr>
    <tr><th>Tileset</th><td>${j.tileset_id} (${escAttr(t.tileset_name)})</td></tr>
    <tr><th>事件数</th><td>${j.events.length}</td></tr>
    <tr><th>BGM</th><td>${j.bgm && j.bgm.audio ? escAttr(j.bgm.audio[0]) : '无'}</td></tr>
  </table>`;
}

/* ---------- 绘制交互 ---------- */
function setTileAt(x, y, id) {
  if (!state.cur) return;
  if (x < 0 || y < 0 || x >= state.cur.width || y >= state.cur.height) return;
  const l = +$('#layerSel').value;
  if (state.cur.layers[l][y][x] === id) return;
  state.cur.layers[l][y][x] = id;
  markDirty();
}

/* 整块绘制 (多选画笔), 以 (ax,ay) 为左上角 */
function paintGrid(ax, ay, grid) {
  const W = state.cur.width, H = state.cur.height;
  let any = false;
  for (let r = 0; r < grid.rows; r++)
    for (let c = 0; c < grid.cols; c++) {
      const x = ax + c, y = ay + r;
      if (x < 0 || y < 0 || x >= W || y >= H) continue;
      const id = grid.tiles[r * grid.cols + c];
      if (!id) continue;
      const l = +$('#layerSel').value;
      if (state.cur.layers[l][y][x] !== id) { state.cur.layers[l][y][x] = id; any = true; }
    }
  if (any) markDirty();
}

function fillRectArea(x0, y0, x1, y1, id) {
  const l = +$('#layerSel').value;
  const W = state.cur.width, H = state.cur.height;
  const ax = Math.max(0, Math.min(x0, x1)), ay = Math.max(0, Math.min(y0, y1));
  const bx = Math.min(W - 1, Math.max(x0, x1)), by = Math.min(H - 1, Math.max(y0, y1));
  let changed = false;
  for (let y = ay; y <= by; y++)
    for (let x = ax; x <= bx; x++)
      if (state.cur.layers[l][y][x] !== id) { state.cur.layers[l][y][x] = id; changed = true; }
  if (changed) markDirty();
}

function floodFill(x, y, id) {
  const l = +$('#layerSel').value;
  const layer = state.cur.layers[l];
  const W = state.cur.width, H = state.cur.height;
  if (x < 0 || y < 0 || x >= W || y >= H) return;
  const target = layer[y][x];
  if (target === id) return;
  const stack = [[x, y]];
  let changed = false;
  while (stack.length) {
    const [cx, cy] = stack.pop();
    if (cx < 0 || cy < 0 || cx >= W || cy >= H) continue;
    if (layer[cy][cx] !== target) continue;
    layer[cy][cx] = id; changed = true;
    stack.push([cx + 1, cy], [cx - 1, cy], [cx, cy + 1], [cx, cy - 1]);
  }
  if (changed) markDirty();
}

function markDirty() { state.dirty = true; setStatus('● 有未保存修改'); }

/* ---------- 拾取瓦片 (Ctrl+点击地图 / 取色工具) ---------- */
function pickTileAt(x, y) {
  if (!state.cur) return;
  if (x < 0 || y < 0 || x >= state.cur.width || y >= state.cur.height) return;
  const l = +$('#layerSel').value;
  let id = state.cur.layers[l][y][x];
  if (!id) {   // 当前层为空则从高到低找非空
    for (let z = state.cur.layers.length - 1; z >= 0; z--) {
      if (state.cur.layers[z][y][x]) { id = state.cur.layers[z][y][x]; break; }
    }
  }
  if (id) {
    selectTile(id, true);
    setStatus(`已拾取瓦片 id=${id}${id < AUTOTILE_OFFSET ? ' (autotile ' + (autotileSlot(id) + 1) + ')' : ' (图块B)'}`);
  } else {
    setStatus('该位置无瓦片');
  }
}

/* ---------- 交互绑定 ---------- */
function bindCanvas() {
  const c = $('#mapCanvas');
  c.addEventListener('mousedown', e => {
    const p = canvasPos(e);
    if (e.ctrlKey) { pickTileAt(p.x, p.y); return; }
    const tool = $('#toolSel').value;
    if (tool === 'select') {
      // 找命中事件 (倒序=最上层)
      const hit = [...(state.cur.events || [])].reverse().find(ev => ev.x === p.x && ev.y === p.y);
      if (hit) {
        selectEvent(hit.id);
        snapshot();
        state.drag = { type: 'move', ev: hit };
        return;
      }
      return;
    }
    if (tool === 'pick') { pickTileAt(p.x, p.y); return; }
    if (tool === 'fill' && state.selectedTile) {
      snapshot();
      floodFill(p.x, p.y, state.selectedTile);
      render();
      return;
    }
    if (tool === 'rect' && state.selectedTile) {
      snapshot();
      state.drag = { type: 'rect', x0: p.x, y0: p.y, x1: p.x, y1: p.y, id: state.selectedTile };
      render();
      return;
    }
    if (tool === 'paint' && (state.selectedTile || state.selGrid)) {
      snapshot();
      if (state.selGrid) { paintGrid(p.x, p.y, state.selGrid); state.drag = { type: 'paintGrid', grid: state.selGrid }; }
      else { setTileAt(p.x, p.y, state.selectedTile); state.drag = { type: 'paint', id: state.selectedTile }; }
      render();
    } else if (tool === 'erase') {
      snapshot();
      setTileAt(p.x, p.y, 0);
      state.drag = { type: 'erase' };
      render();
    }
  });
  c.addEventListener('mousemove', e => {
    const p = canvasPos(e);
    if (!state.drag) {
      // 悬停预览 (仅在移动到新格时重绘)
      if (!state.hover || state.hover.x !== p.x || state.hover.y !== p.y) {
        state.hover = p;
        render();
      }
      return;
    }
    if (state.drag.type === 'paint') { setTileAt(p.x, p.y, state.drag.id); render(); }
    else if (state.drag.type === 'paintGrid') { paintGrid(p.x, p.y, state.drag.grid); render(); }
    else if (state.drag.type === 'erase') { setTileAt(p.x, p.y, 0); render(); }
    else if (state.drag.type === 'rect') { state.drag.x1 = p.x; state.drag.y1 = p.y; render(); }
    else if (state.drag.type === 'move') {
      if (p.x >= 0 && p.y >= 0 && p.x < state.cur.width && p.y < state.cur.height) {
        state.drag.ev.x = p.x; state.drag.ev.y = p.y;
        $('#evX').value = p.x; $('#evY').value = p.y;
        markDirty(); render();
      }
    }
  });
  c.addEventListener('mouseleave', () => {
    if (!state.drag && state.hover) { state.hover = null; render(); }
  });
  window.addEventListener('mouseup', () => {
    if (state.drag && state.drag.type === 'rect') {
      fillRectArea(state.drag.x0, state.drag.y0, state.drag.x1, state.drag.y1, state.drag.id);
      render();
    }
    state.drag = null;
  });
  window.addEventListener('keydown', e => {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'z') {
      e.preventDefault();
      undo();
      return;
    }
    // 输入框/下拉框聚焦时不响应工具快捷键
    const tag = (e.target && e.target.tagName) || '';
    if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return;
    if (e.ctrlKey || e.metaKey || e.altKey) return;
    const k = e.key.toLowerCase();
    if (k === 'p' || k === 'e') {
      $('#toolSel').value = k === 'p' ? 'paint' : 'erase';
      $('#toolSel').dispatchEvent(new Event('change'));   // 复用 change 提示逻辑
    }
  });
}

/* ---------- 保存 ---------- */
async function save() {
  if (!state.cur) return;
  setStatus('保存中...');
  try {
    const payload = {
      id: state.cur.id, width: state.cur.width, height: state.cur.height,
      layers: state.cur.layers, events: state.cur.events,
    };
    const r = await api('/api/save', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    state.dirty = false;
    state.in_mod = true;
    setStatus(`已保存 → ${r.saved}`);
  } catch (e) {
    setStatus('保存失败: ' + e.message);
  }
}

async function restore() {
  if (!state.cur) return;
  if (!confirm(`恢复原版地图 #${state.cur.id}？将删除 mod 覆盖，未保存修改会丢失。`)) return;
  await api('/api/restore', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ id: state.cur.id }) });
  await loadMap(state.cur.id);
  setStatus('已恢复原版地图');
}

/* ---------- 初始化 ---------- */
async function init() {
  bindCanvas();
  state.maps = await api('/api/maps');
  const sel = $('#mapSel');
  const nameById = {};
  state.maps.forEach(m => { nameById[m.id] = m; });
  // 按 id 排序, 标注 mod
  [...state.maps].sort((a, b) => a.id - b.id).forEach(m => {
    const o = document.createElement('option');
    o.value = m.id;
    o.textContent = `${m.id}: ${m.name}${m.in_mod ? ' ★' : ''}`;
    sel.appendChild(o);
  });
  sel.addEventListener('change', () => loadMap(+sel.value));
  $('#zoom').addEventListener('change', render);
  $('#gridChk').addEventListener('change', render);
  $('#layerSel').addEventListener('change', () => { setStatus(`当前图层: 层${$('#layerSel').value}`); });
  $('#toolSel').addEventListener('change', () => {
    const t = $('#toolSel').value;
    const tips = { paint: '画笔: 点击/拖拽绘制', rect: '矩形: 拖拽框选区域填充', fill: '填充: 点击连通区域整体填充',
                   pick: '取色: 点击地图取瓦片', erase: '橡皮: 点击清除', select: '选择事件: 点击选中, 拖拽移动, 双击打开详情' };
    setStatus(tips[t] || t);
  });
  $('#btnSave').addEventListener('click', save);
  $('#btnRestore').addEventListener('click', restore);

  // tab 切换
  document.querySelectorAll('.tab').forEach(t => {
    t.addEventListener('click', () => {
      document.querySelectorAll('.tab').forEach(x => x.classList.remove('active'));
      t.classList.add('active');
      document.querySelectorAll('.tabbody').forEach(b => b.style.display = 'none');
      $('#tab-' + t.dataset.tab).style.display = 'block';
    });
  });

  // 双击事件详情 (从地图)
  $('#mapCanvas').addEventListener('dblclick', e => {
    const p = canvasPos(e);
    const hit = [...(state.cur.events || [])].reverse().find(ev => ev.x === p.x && ev.y === p.y);
    if (hit) { selectEvent(hit.id); document.querySelector('.tab[data-tab=events]').click(); }
  });

  if (state.maps.length) {
    sel.value = 12;
    await loadMap(12);
  } else {
    setStatus('未找到地图');
  }
}

window.addEventListener('DOMContentLoaded', init);
