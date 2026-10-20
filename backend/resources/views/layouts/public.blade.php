<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>@yield('title') · S-Delivery</title>
    <style>
        :root { --brand: #C6FF3D; --ink: #111111; --muted: #555555; --line: #ececec; }
        * { box-sizing: border-box; }
        body { margin: 0; background: #fafafa; color: var(--ink); font: 16px/1.6 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
        header { background: var(--ink); color: var(--brand); padding: 18px 16px; }
        header .wrap { display: flex; align-items: center; gap: 12px; }
        .logo { display: inline-flex; align-items: center; justify-content: center; width: 40px; height: 40px; border-radius: 10px; background: var(--brand); color: var(--ink); font-weight: 800; }
        header strong { font-size: 1.15rem; letter-spacing: .02em; }
        .wrap { max-width: 760px; margin: 0 auto; }
        main { padding: 24px 16px 48px; }
        h1 { font-size: 1.6rem; line-height: 1.25; margin: 0 0 6px; }
        h2 { font-size: 1.15rem; margin: 28px 0 8px; padding-left: 10px; border-left: 4px solid var(--brand); }
        p, li { color: #222; }
        .muted { color: var(--muted); font-size: .9rem; }
        .card { background: #fff; border: 1px solid var(--line); border-radius: 12px; padding: 16px 18px; margin: 16px 0; }
        .steps { counter-reset: s; list-style: none; padding: 0; }
        .steps li { counter-increment: s; position: relative; padding-left: 40px; margin: 10px 0; }
        .steps li::before { content: counter(s); position: absolute; left: 0; top: 0; width: 28px; height: 28px; border-radius: 50%; background: var(--brand); color: var(--ink); font-weight: 700; display: flex; align-items: center; justify-content: center; }
        a { color: var(--ink); text-decoration-color: var(--brand); text-decoration-thickness: 2px; }
        .btn { display: inline-block; background: var(--ink); color: var(--brand); padding: 10px 16px; border-radius: 10px; text-decoration: none; font-weight: 600; margin: 4px 8px 4px 0; }
        footer { border-top: 1px solid var(--line); padding: 16px; font-size: .85rem; color: var(--muted); }
        footer a { margin-right: 14px; }
        @media (max-width: 480px) { h1 { font-size: 1.35rem; } }
    </style>
</head>
<body>
    <header>
        <div class="wrap">
            <span class="logo">V</span>
            <strong>S-Delivery</strong>
        </div>
    </header>
    <main class="wrap">
        @yield('content')
    </main>
    <footer>
        <div class="wrap">
            <a href="{{ route('legal.privacy') }}">Politique de confidentialité</a>
            <a href="{{ route('legal.account-deletion') }}">Supprimer mon compte</a>
            <span>© {{ date('Y') }} S-Delivery · Lomé, Togo</span>
        </div>
    </footer>
</body>
</html>
