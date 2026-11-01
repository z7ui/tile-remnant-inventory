<?php
/**
 * 下载中转页：微信里打开 APK 链接会提示，这里检测 User-Agent，
 * 微信内置浏览器（MicroMessenger）显示「右上角浏览器打开」引导，
 * 普通浏览器直接 302 跳到真实下载地址。
 *
 * 用法：https://www.z7ui.cn/d/<文件名>.apk
 */
declare(strict_types=1);

$path = $_SERVER['REQUEST_URI'] ?? '';
$file = '';
if (preg_match('#^/d/([A-Za-z0-9._-]+\.apk)$#', $path, $m)) {
    $file = $m[1];
}

$real = '/opt/apps-archive/downloads/' . $file;
if ($file === '' || !is_file($real)) {
    http_response_code(404);
    header('Content-Type: text/plain; charset=utf-8');
    echo '文件不存在。';
    exit;
}

$ua = $_SERVER['HTTP_USER_AGENT'] ?? '';
$isWechat = strpos($ua, 'MicroMessenger') !== false;

if (!$isWechat) {
    header('Location: /apps-archive/downloads/' . rawurlencode($file), true, 302);
    exit;
}

$size = filesize($real);
$sizeText = $size > 0 ? sprintf('%.1f MB', $size / 1048576) : '未知大小';
$h = htmlspecialchars($file, ENT_QUOTES, 'UTF-8');
header('Content-Type: text/html; charset=utf-8');
?>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>下载 <?php echo $h; ?></title>
<style>
  :root { color-scheme: light dark; }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC",
      "Microsoft YaHei", sans-serif;
    background: #f5f6f8; color: #1f2328;
    display: flex; align-items: center; justify-content: center;
    min-height: 100vh; padding: 24px;
  }
  @media (prefers-color-scheme: dark) {
    body { background: #111418; color: #e6e8eb; }
    .card { background: #1c2025 !important; border-color: #30363d !important; }
    .file { background: #24292f !important; }
  }
  .card {
    background: #fff; border: 1px solid #e5e7eb; border-radius: 16px;
    padding: 32px 24px; max-width: 400px; width: 100%; text-align: center;
    box-shadow: 0 8px 30px rgba(0,0,0,0.06);
  }
  .icon { font-size: 48px; line-height: 1; margin-bottom: 16px; }
  h1 { font-size: 18px; font-weight: 600; margin-bottom: 8px; }
  .file {
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 13px; color: #57606a; background: #f6f8fa;
    border-radius: 8px; padding: 6px 10px; display: inline-block;
    margin-bottom: 4px; word-break: break-all;
  }
  .size { font-size: 12px; color: #8b949e; margin-bottom: 20px; }
  .tip { font-size: 15px; line-height: 1.6; margin-bottom: 16px; }
  .arrow {
    display: inline-block; font-size: 22px; color: #0969da; font-weight: 700;
    background: #ddf4ff; border-radius: 8px; padding: 2px 12px; margin: 0 4px;
  }
  .steps { font-size: 14px; margin-bottom: 24px; }
  button {
    width: 100%; padding: 12px; font-size: 15px; font-weight: 600;
    color: #fff; background: #1f6feb; border: none; border-radius: 10px;
    cursor: pointer;
  }
  button:active { opacity: 0.85; }
  .copied { margin-top: 10px; font-size: 13px; color: #1a7f37; display: none; }
</style>
</head>
<body>
  <div class="card">
    <div class="icon">📦</div>
    <h1>微信内无法直接下载安装包</h1>
    <div class="file"><?php echo $h; ?></div>
    <div class="size"><?php echo $sizeText; ?></div>
    <p class="tip">请点击右上角<span class="arrow">⋯</span>，选择「在浏览器打开」</p>
    <div class="steps">打开后会自动开始下载</div>
    <button id="copyBtn" type="button">复制下载链接</button>
    <div class="copied" id="copied">已复制，去浏览器粘贴打开即可</div>
  </div>
  <script>
    (function () {
      var url = location.href;
      var btn = document.getElementById('copyBtn');
      var copied = document.getElementById('copied');
      btn.addEventListener('click', function () {
        function done() {
          copied.style.display = 'block';
          setTimeout(function () { copied.style.display = 'none'; }, 2500);
        }
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(url).then(done).catch(function () { fallback(); });
        } else { fallback(); }
        function fallback() {
          var ta = document.createElement('textarea');
          ta.value = url; document.body.appendChild(ta);
          ta.select(); document.execCommand('copy'); document.body.removeChild(ta);
          done();
        }
      });
    })();
  </script>
</body>
</html>
