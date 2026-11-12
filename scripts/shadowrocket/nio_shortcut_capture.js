/**
 * 🎛 YumikoToys NIO-Dash — 场景快捷链路捕获（http-response）
 * 配合 YumikoToys-NIO.sgmodule v3.3 使用
 *
 * 逆向背景（来自官方 App 二进制分析）：
 *   官方 App「快捷场景」走 icar.nio.com /api/2/rvs/km/shortcut/ 端点族（KnowMe 服务）：
 *     /my/list        已添加场景列表（POST，body 为 gson JsonObject）
 *     /my/add /my/delete /my/update   场景增删改
 *     /official/category/list         官方场景分类
 *   实测：POST + 空 body 能过 md5_full 签名，body 非空则 403 invalid sign ——
 *   该服务族的 body 参与签名方式与车控通道（tsp/api/1/vehicle/command 档位A/B）均不同，
 *   纯盲猜 20+ 变体未命中，需要官方客户端真实请求原文作对照。
 *
 * 本脚本拦截 km/shortcut 全部响应，把 请求方法/URL/body/Authorization + 响应原文
 * 存档并直推 YumikoToys App 诊断（127.0.0.1:8997/credentials，category=shortcut_capture）：
 *   1. 还原 POST body 签名的真实拼串（对照 query/body 结构）
 *   2. 拿到场景列表响应的模型字段（scene_id/scene_name/scene_code…），用于 App 移植
 */

const LOCAL_PUSH_URL = "http://127.0.0.1:8997/credentials";
const STORE_KEY      = "nio_shortcut_samples";
const MAX_SAMPLES    = 8;
const MAX_BODY_LEN   = 3000;

(function main() {
    const url = ($request && $request.url) || "";
    // 只关心快捷场景端点族（KnowMe 服务）
    if (!/km\/shortcut/i.test(url)) { $done({}); return; }

    const method = (($request && $request.method) || "GET").toUpperCase();
    const headers = ($request && $request.headers) || {};
    const reqBody = ($request && typeof $request.body === "string") ? $request.body : "";
    const auth = headers["Authorization"] || headers["authorization"] || "";

    let status = 0, respBody = "";
    if ($response) {
        status = $response.status || 0;
        respBody = typeof $response.body === "string" ? $response.body : "";
    }
    if (respBody.length > MAX_BODY_LEN) respBody = respBody.slice(0, MAX_BODY_LEN) + "…(截断)";

    // 去重指纹：method + path + query(去 timestamp/sign) + body + 响应前缀
    const qpart = (url.split("?")[1] || "").split("&")
        .filter(function(kv) { return kv && !/^timestamp=/.test(kv) && !/^sign=/.test(kv); })
        .sort().join("&");
    const fp = method + "|" + (url.split("?")[0] || "") + "|" + qpart + "|" + reqBody + "|" + status + "|" + respBody.slice(0, 200);

    let samples = [];
    try { samples = JSON.parse($persistentStore.read(STORE_KEY) || "[]"); } catch (_) {}
    if (samples.some(function(s) { return s._fp === fp; })) { $done({}); return; }

    const sample = {
        time:      new Date().toLocaleTimeString("zh-CN", { hour12: false }),
        method:    method,
        url:       url,
        req_body:  reqBody.slice(0, MAX_BODY_LEN),
        auth:      auth,
        status:    status,
        resp_body: respBody,
        _fp:       fp
    };
    samples = [sample].concat(samples).slice(0, MAX_SAMPLES);
    $persistentStore.write(JSON.stringify(samples), STORE_KEY);

    // 直推 App（fire-and-forget，不阻塞响应）
    $httpClient.post({
        url: LOCAL_PUSH_URL,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ shortcut_samples: samples, source: "shadowrocket_shortcut" })
    }, function(err, resp, _) {
        console.log(err ? "[YumikoToys] App 未在前台，快捷场景样本已存 BoxJS" : "[YumikoToys] ✅ 快捷场景样本已直推 App");
    });

    try {
        if (typeof $notification !== "undefined") {
            const path = (url.split("?")[0].split("/").slice(-2).join("/")) || url;
            $notification.post("🎛 已捕获快捷场景链路", path + " · status " + status, "已直推 App 诊断（shortcut_capture）");
        }
    } catch (_) {}

    $done({});
})();
