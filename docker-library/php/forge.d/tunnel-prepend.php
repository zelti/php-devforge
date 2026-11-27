<?php
// Makes an app reachable through `forge tunnel` when it stores its own base URL.
//
// The tunnel already hands PHP the public Host, and an app that builds links
// from the request (Laravel, Symfony) needs nothing more. One that keeps its
// URL in the database or in config (WordPress's `home`/`siteurl`) does not: its
// links, assets and redirects all point at <site>.phpforge.dev, a name a phone
// cannot reach. Rewriting only the HTML is not enough either -- the app sees
// a host that is not its own, redirects to the local one, that redirect gets
// rewritten back to the tunnel, and the browser loops.
//
// FORGE_TUNNEL_ORIGIN is set by the web server (resolve_docroot.lua, Apache
// and nginx), never by the client: it is present only for a host with a
// .tunnel/ alias, and holds the local name forge gave cloudflared as SNI.
//
// Two layers, both only on a tunnel request:
//  - generic: the response body and the redirect-type headers get
//    //<local> replaced with //<public>, in plain, JSON-escaped and
//    URL-encoded form. "//" covers https:, http: and scheme-relative URLs.
//  - WordPress: home/siteurl are filtered to the public host before WordPress
//    reads them, so its canonical redirect stops pointing back home.

(static function (): void {
    $origin = $_SERVER['FORGE_TUNNEL_ORIGIN'] ?? '';
    $public = strtolower(explode(':', $_SERVER['HTTP_HOST'] ?? '')[0]);
    $valid = '/^[a-z0-9-]+(\.[a-z0-9-]+)+$/';
    if (PHP_SAPI === 'cli' || !preg_match($valid, $origin) || !preg_match($valid, $public)
        || $origin === $public) {
        return;
    }

    $map = [
        '//' . $origin     => '//' . $public,
        '\/\/' . $origin   => '\/\/' . $public,
        '%2F%2F' . $origin => '%2F%2F' . $public,
        '%2f%2f' . $origin => '%2f%2f' . $public,
    ];
    $swap = static fn (string $s): string => strtr($s, $map);

    // WordPress, detected by its loader rather than guessed. $wp_filter set
    // before wp-settings.php runs is turned into real hooks by
    // WP_Hook::build_preinitialized_hooks(), which is what lets a filter
    // exist before any plugin can add one. A filter on the option, rather than
    // defining WP_HOME: it keeps a path (WordPress in a subfolder) intact, and
    // does not collide with a wp-config.php that defines the constant itself.
    // A wp-config.php that hard-codes WP_HOME to the local name wins over
    // this, and that site will still redirect home.
    $root = rtrim($_SERVER['DOCUMENT_ROOT'] ?? '', '/');
    if ($root !== '' && is_file($root . '/wp-load.php')) {
        $hook = ['function' => $swap, 'accepted_args' => 1];
        foreach (['option_home', 'option_siteurl'] as $name) {
            $GLOBALS['wp_filter'][$name][10][] = $hook;
        }
    }

    // Headers: rewritten just before they go out. Set-Cookie too, for a cookie
    // scoped with domain=<local>, which the browser would drop on the public
    // host -- and with it any login. Only one header callback can exist per
    // request; an app registering its own replaces this one.
    $cookie = '/(;\s*domain=)\.?' . preg_quote($origin, '/') . '(?=\s*(;|$))/i';
    header_register_callback(static function () use ($swap, $cookie, $public): void {
        $by = [];
        foreach (headers_list() as $line) {
            [$name, $value] = array_map('trim', explode(':', $line, 2)) + [1 => ''];
            $by[strtolower($name)][] = [$name, $value];
        }
        foreach (['location', 'content-location', 'link', 'refresh', 'set-cookie'] as $key) {
            if (!isset($by[$key])) {
                continue;
            }
            $new = array_map(static fn ($h) => [$h[0], $key === 'set-cookie'
                ? preg_replace($cookie, '${1}' . $public, $h[1])
                : $swap($h[1])], $by[$key]);
            if ($new === $by[$key]) {
                continue;
            }
            header_remove($by[$key][0][0]);
            foreach ($new as [$name, $value]) {
                header("$name: $value", false);
            }
        }
    });

    // Body: buffered whole (chunk size 0), so a URL is never split across two
    // chunks. Only text is touched; anything else, or a body the app already
    // compressed itself, passes through as is. Removable, so an app that
    // streams a download can still end it with ob_end_flush() first.
    ob_start(static function (string $buffer, int $phase) use ($swap): string {
        static $skip = null;
        if ($skip === null) {
            $type = '';
            $skip = false;
            foreach (headers_list() as $line) {
                $lower = strtolower($line);
                if (str_starts_with($lower, 'content-type:')) {
                    $type = $lower;
                } elseif (str_starts_with($lower, 'content-encoding:')) {
                    $skip = true;
                }
            }
            // No Content-Type yet means PHP's default, text/html.
            if (!$skip && $type !== ''
                && !preg_match('#(text/|json|javascript|xml)#', $type)) {
                $skip = true;
            }
        }
        if ($skip) {
            return $buffer;
        }
        $out = $swap($buffer);
        // A length the app declared no longer matches. Only possible while the
        // headers are still unsent, i.e. on the first pass through here.
        if ($out !== $buffer && ($phase & PHP_OUTPUT_HANDLER_START) && !headers_sent()) {
            header_remove('Content-Length');
        }
        return $out;
    });
})();
