/**
 * 🐰 YumikoToys NIO-Dash — 蔚来凭证直推脚本
 * 配合 YumikoToys-NIO.sgmodule 使用
 *
 * 工作原理：
 *   Shadowrocket 开启 MITM 后，此脚本拦截 *.nio.com 请求，
 *   提取 Authorization Token + URL 参数，
 *   直接 POST 到手机本地 http://127.0.0.1:8997/credentials，
 *   YumikoToys App 收到后自动回填并震动通知。
 *
 * 兜底：写入 $persistentStore，Safari 打开 http://boxjs.com 可手动复制。
 */

const LOCAL_PUSH_URL      = "http://127.0.0.1:8997/credentials";
const STORE_KEY           = "nio_sniff_data";
const DEFAULT_CHANGE_URL  = "https://gateway-front-external.nio.com/moat/1100367/api/v1/otd/car/ext/general/serviceOrder/getTabOrder?offset=0&limit=200&orderTypes=pe_shaman,pe_shaman_change,service_pe_discharge,battery_flexible_upgrade,nsom_so_maintenance,nsom_so_chauffeur,chauffeur_vehicle_delivery,so_case_accident&hash_type=sha256&lang=zh&region=US&tz_offset=28800&app_ver=6.5.3";
const DEFAULT_CHECKIN_URL = "https://gateway-front-external.nio.com/moat/10086/n/c/award/square?event=checkin&collection_id=1843940587332317185";

(function main() {
    const url     = $request.url;
    const headers = $request.headers || {};

    // ── 内嵌看板页（Safari 打开 http://boxjs.com）──
    if (url.includes("boxjs.com") || url.includes("boxjs.net") ||
        url.includes("nio.toys")  || url.includes("nio.local")) {
        $done({ response: { status: 200, headers: { "Content-Type": "text/html;charset=utf-8" }, body: buildHtml() } });
        return;
    }

    // ── 提取 Bearer Token ──
    let token = headers["Authorization"] || headers["authorization"] || "";
    if (token.startsWith("Bearer ")) token = token.slice(7).trim();

    // ── 提取 URL 参数 ──
    const qp = parseQS(url);

    // ── 无有效凭证则跳过 ──
    if (!token && !qp.vehicle_id) { $done({}); return; }

    // ── 读/更新持久化存储 ──
    let store = {};
    try { store = JSON.parse($persistentStore.read(STORE_KEY) || "{}"); } catch (_) {}

    if (token)         store.vehicle_token = token;
    if (qp.vehicle_id) store.vehicle_id    = qp.vehicle_id;
    if (qp.device_id)  store.device_id     = qp.device_id;
    if (qp.sign)       store.sign          = qp.sign;
    if (qp.timestamp)  store.timestamp     = qp.timestamp;

    const isRvs    = url.includes("icar.nio.com") && url.includes("/status");
    const isWidget = url.includes("/widget/info");

    store.change_url  = DEFAULT_CHANGE_URL;
    store.checkin_url = DEFAULT_CHECKIN_URL;
    if (token) { store.change_token = token; store.checkin_token = token; }

    if (isRvs) {
        store.mode = "url"; store.vehicle_url = url; store.tyre_ready = true;
    } else if (isWidget) {
        store.widget_url = url;
        if (!store.vehicle_url || store.mode === "widget") { store.vehicle_url = url; store.mode = "widget"; }
    }

    $persistentStore.write(JSON.stringify(store, null, 2), STORE_KEY);

    // ── 直推到 YumikoToys App ──
    const payload = JSON.stringify({
        vehicle_token: store.vehicle_token || "",
        vehicle_id:    store.vehicle_id    || "",
        device_id:     store.device_id     || "",
        vehicle_url:   store.vehicle_url   || "",
        sign:          store.sign          || "",
        timestamp:     store.timestamp     || "",
        source:        "shadowrocket_module"
    });

    $httpClient.post({ url: LOCAL_PUSH_URL, headers: { "Content-Type": "application/json" }, body: payload },
        function(err, resp, _) {
            const ok = !err && resp && resp.status < 300;
            console.log(ok ? "[YumikoToys] ✅ 凭证已直推 App" : "[YumikoToys] App 未在前台，凭证已存入 BoxJS");
        }
    );

    // ── Shadowrocket 系统通知 ──
    try {
        if (typeof $notification !== "undefined") {
            const title = isRvs ? "🎉 蔚来完整凭证已捕获！" : "🔑 Token 已捕获";
            const body  = isRvs ? "含 4 轮胎压，App 自动回填中" : "请在蔚来 App 爱车页下拉刷新获取完整凭证";
            $notification.post(title, body, "");
        }
    } catch (_) {}

    $done({});
})();

// ────── 工具函数 ──────

function parseQS(u) {
    const p = {}, qi = u.indexOf("?");
    if (qi < 0) return p;
    u.slice(qi + 1).split("&").forEach(function(kv) {
        const i = kv.indexOf("=");
        if (i > 0) {
            try { p[decodeURIComponent(kv.slice(0, i))] = decodeURIComponent(kv.slice(i + 1)); }
            catch (_) { p[kv.slice(0, i)] = kv.slice(i + 1); }
        }
    });
    return p;
}

function buildHtml() {
    let store = {};
    try { store = JSON.parse($persistentStore.read(STORE_KEY) || "{}"); } catch (_) {}
    const json    = JSON.stringify(store, null, 2);
    const hasData = !!(store.vehicle_token || store.vehicle_url);
    return `<!DOCTYPE html>
<html lang="zh-CN"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<title>🐰 蔚来凭证看板</title>
<style>
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#0f172a;color:#f8fafc;margin:0;padding:20px;display:flex;flex-direction:column;align-items:center}
.card{background:#1e293b;border-radius:20px;padding:24px;width:100%;max-width:480px;border:1px solid #334155;margin-top:10px}
h2{margin:0 0 8px;font-size:20px;color:#38bdf8}
p{color:#94a3b8;font-size:13px;margin:0 0 16px;line-height:1.5}
.badge{display:inline-block;padding:6px 12px;border-radius:99px;font-size:13px;font-weight:700;
  background:${hasData?"rgba(34,197,94,.2)":"rgba(234,179,8,.2)"};
  color:${hasData?"#4ade80":"#facc15"};margin-bottom:16px;
  border:1px solid ${hasData?"rgba(34,197,94,.3)":"rgba(234,179,8,.3)"}}
textarea{width:100%;height:220px;background:#090d16;color:#38bdf8;border:1px solid #334155;border-radius:12px;padding:12px;font-family:monospace;font-size:12px;resize:none;outline:none}
button{width:100%;background:linear-gradient(135deg,#0284c7,#0ea5e9);color:#fff;border:none;padding:15px;border-radius:14px;font-size:16px;font-weight:700;margin-top:16px;cursor:pointer}
.tip{margin-top:16px;font-size:12px;color:#64748b;text-align:center}
</style></head><body>
<div class="card">
<h2>🐰 蔚来看板配置提取器</h2>
<p>由 YumikoToys NIO-Dash Shadowrocket 模块提取</p>
<div class="badge">${hasData?"✅ 已捕获凭证 — 复制后粘贴到 App":"⏳ 暂未捕获，请进入蔚来 App 下拉刷新"}</div>
<textarea id="j" readonly>${json}</textarea>
<button onclick="cp()">📋 一键复制配置到剪贴板</button>
<div class="tip">复制后打开 YumikoToys App → 设置 → 「剪贴板读取并识别」</div>
</div>
<script>
function cp(){
  const t=document.getElementById('j').value;
  const b=document.querySelector('button');
  if(navigator.clipboard){navigator.clipboard.writeText(t);}
  else{document.getElementById('j').select();document.execCommand('copy');}
  b.textContent='✅ 已复制！切换回 YumikoToys App';
  b.style.background='linear-gradient(135deg,#16a34a,#22c55e)';
  setTimeout(()=>{b.textContent='📋 一键复制配置到剪贴板';b.style.background='linear-gradient(135deg,#0284c7,#0ea5e9)'},3000);
}
</script></body></html>`;
}
