<?php // written by install.sh -- delete this line to keep your own version
/**
 * The page you land on after installing, and the one to open when something is
 * off: everything below is probed live rather than described.
 *
 * Copied into <projects>/sites/welcome/ by install.sh. No build step, no CDN --
 * it has to work on a machine with no internet, which is the point of the whole
 * environment.
 */

/** Is something listening? An absent host on the compose network fails at once. */
function up(string $host, int $port): bool
{
    $sock = @stream_socket_client("tcp://$host:$port", $e, $s, 0.25);
    if ($sock === false) {
        return false;
    }
    fclose($sock);
    return true;
}

$host = $_SERVER['HTTP_HOST'] ?? 'localhost';
$here = preg_replace('/^.*?\./', '', $host);          // phpforge.dev
$label = strtok($host, '.');                          // welcome--sites--p85
$plain = preg_replace('/--p\d\d$/', '', $label);      // welcome--sites

/** The same page, served by another version: swap the --pNN suffix. */
function version_url(string $plain, string $domain, string $v): string
{
    return sprintf('https://%s--p%s.%s/', $plain, $v, $domain);
}

// One entry per service the compose files can start. Ports are the ones inside
// the network, not the ones published on your machine.
$versions = ['8.3' => 'php83dev', '8.4' => 'php84dev', '8.5' => 'php85dev'];
$services = [
    'PostgreSQL 16' => ['postgres16dev', 5432], 'PostgreSQL 17' => ['postgres17dev', 5432],
    'PostgreSQL 18' => ['postgres18dev', 5432], 'MariaDB 11' => ['mariadb11dev', 3306],
    'MariaDB 12' => ['mariadb12dev', 3306], 'Elasticsearch' => ['es8143dev', 9200],
];

// Which web server proxied this request. Apache sends "Apache/2.4.68 (Debian)";
// the nginx image passes "nginx/<version>" through fastcgi_params. Worth saying
// out loud: the two are swappable here, and .htaccess only works on one of them.
$server = $_SERVER['SERVER_SOFTWARE'] ?? '';
if (preg_match('~^(apache|nginx|openresty)[/ ]*([\d.]*)~i', $server, $m)) {
    $web = strtolower($m[1]) === 'apache' ? 'Apache' : 'nginx';
    $web .= $m[2] !== '' ? ' ' . $m[2] : '';
    $web .= strtolower($m[1]) !== 'apache' ? ' (OpenResty)' : '';
} else {
    $web = $server !== '' ? $server : 'unknown';
}

$mail = up('mailpit', 1025);
$running = PHP_MAJOR_VERSION . '.' . PHP_MINOR_VERSION;

// The path you would type, on your machine -- install.sh substitutes it when it
// copies this file. Inside the container the folder has a different name, and
// telling you to cd there would be useless. Without the installer, fall back to
// what the file itself knows.
$projects = '__PROJECTS_DIR__';
if (str_starts_with($projects, '__PROJECTS')) {
    $projects = dirname(dirname(dirname(__FILE__)));
}

// Also substituted at copy time -- the page cannot see the checkout.
$version = '__FORGE_VERSION__';
if (str_starts_with($version, '__FORGE')) {
    $version = '';
}
?>
<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>PHP DevForge</title>
<style>
:root {
  color-scheme: light dark;
  --bg: #fbfbfd; --fg: #1c1c1f; --muted: #6b6b75; --line: #e4e4ea;
  --card: #fff; --ok: #1a7f4b; --off: #9a9aa3; --link: #b8562f;
}
@media (prefers-color-scheme: dark) {
  :root { --bg: #131317; --fg: #ececf1; --muted: #9a9aa6; --line: #2a2a33;
          --card: #1b1b21; --ok: #3ecf8e; --off: #6b6b75; --link: #e08a5c; }
}
* { box-sizing: border-box }
body { margin: 0; padding: 3rem 1.5rem 4rem; background: var(--bg); color: var(--fg);
       font: 16px/1.6 system-ui, -apple-system, "Segoe UI", sans-serif }
main { max-width: 46rem; margin: 0 auto }
header { text-align: center; margin-bottom: 2.5rem }
header img { width: 168px; height: auto }
h1 { font-size: 1.5rem; margin: .75rem 0 .25rem; font-weight: 650 }
h2 { font-size: .8rem; text-transform: uppercase; letter-spacing: .08em;
     color: var(--muted); margin: 2rem 0 .75rem; font-weight: 600 }
.sub { color: var(--muted); margin: 0 }
.card { background: var(--card); border: 1px solid var(--line); border-radius: .6rem;
        padding: 1rem 1.25rem }
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(13rem, 1fr)); gap: .5rem }
.row { display: flex; align-items: baseline; gap: .5rem; padding: .3rem 0 }
.dot { flex: none; width: .55rem; height: .55rem; border-radius: 50%; background: var(--off) }
.dot.on { background: var(--ok) }
.k { color: var(--muted); min-width: 7.5rem }
.v { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .92rem;
     word-break: break-all }
code, pre { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .88rem }
pre { background: var(--card); border: 1px solid var(--line); border-radius: .5rem;
      padding: .9rem 1.1rem; overflow-x: auto }
a { color: var(--link) }
.muted { color: var(--muted) }
footer { margin-top: 3rem; padding-top: 1.25rem; border-top: 1px solid var(--line);
         color: var(--muted); font-size: .9rem; text-align: center }
</style>
<main>
  <header>
    <img src="./logo.png" alt="PHP DevForge">
    <h1>PHP DevForge is running</h1>
    <p class="sub">Served by PHP <?= htmlspecialchars(PHP_VERSION) ?> over <?= htmlspecialchars(PHP_SAPI) ?><?=
        extension_loaded('xdebug') ? ' &middot; Xdebug on' : '' ?></p>
  </header>

  <h2>This request</h2>
  <div class="card">
    <div class="row"><span class="k">host</span><span class="v"><?= htmlspecialchars($host) ?></span></div>
    <div class="row"><span class="k">web server</span><span class="v"><?= htmlspecialchars($web) ?></span></div>
    <div class="row"><span class="k">document root</span><span class="v"><?= htmlspecialchars($_SERVER['DOCUMENT_ROOT'] ?? '') ?></span></div>
    <div class="row"><span class="k">this file</span><span class="v"><?= htmlspecialchars(__FILE__) ?></span></div>
  </div>
  <p class="muted">The host name chose that folder and this PHP version. Nothing is
  configured per project.</p>

  <h2>PHP versions</h2>
  <div class="card grid">
    <?php foreach ($versions as $v => $svc): $on = up($svc, 9000);
          $short = str_replace('.', '', $v); ?>
      <div class="row">
        <span class="dot<?= $on ? ' on' : '' ?>"></span>
        <span>
          <?php if ($on): ?>
            <a href="<?= htmlspecialchars(version_url($plain, $here, $short)) ?>">PHP <?= $v ?></a>
            <?= $v === $running ? '<span class="muted">&mdash; serving this page</span>' : '' ?>
          <?php else: ?>
            <span class="muted">PHP <?= $v ?> &mdash; <code>forge php on <?= $v ?></code></span>
          <?php endif ?>
        </span>
      </div>
    <?php endforeach ?>
  </div>

  <h2>Services</h2>
  <div class="card grid">
    <div class="row">
      <span class="dot<?= $mail ? ' on' : '' ?>"></span>
      <span><?= $mail
        ? '<a href="https://mail.' . htmlspecialchars($here) . '/">Mail catcher</a>'
        : '<span class="muted">Mail catcher &mdash; <code>forge mail on</code></span>' ?></span>
    </div>
    <?php foreach ($services as $name => [$svc, $port]): $on = up($svc, $port); ?>
      <div class="row">
        <span class="dot<?= $on ? ' on' : '' ?>"></span>
        <span class="<?= $on ? '' : 'muted' ?>"><?= $name ?><?= $on ? ' <span class="muted">' . htmlspecialchars($svc) . ':' . $port . '</span>' : '' ?></span>
      </div>
    <?php endforeach ?>
  </div>
  <p class="muted">Nothing starts unless you pick it: <code>forge db list</code>,
  <code>forge profile list</code>.</p>

  <h2>Your first project</h2>
  <pre>cd <?= htmlspecialchars($projects) . "\n" ?>ln -s ../projects/my-app/public sites/my-app</pre>
  <p class="muted">&rarr; <code>https://my-app--sites.<?= htmlspecialchars($here) ?></code>
  &nbsp;&middot;&nbsp; or let <code>forge link ~/code/my-app/public</code> do it for you.</p>

  <footer>
    <a href="https://github.com/zelti/php-devforge#readme">Documentation</a> &middot;
    <a href="https://github.com/zelti/php-devforge/blob/main/README.es.md">en español</a> &middot;
    <code>forge help</code>
    <?= $version !== '' ? '<br>PHP DevForge ' . htmlspecialchars($version) : '' ?>
  </footer>
</main>
</html>
