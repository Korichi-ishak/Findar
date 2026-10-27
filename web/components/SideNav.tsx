'use client';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import type { NavItem } from '@/lib/routes';

export function SideNav({ title, sub, items }: { title: string; sub?: string; items: NavItem[] }) {
  const path = usePathname();
  const isCurrent = (href: string) =>
    path === href || (href.split('/').length > 2 && path.startsWith(href + '/'));
  let lastGroup: string | undefined;
  return (
    <nav className="side" aria-label={title}>
      <div className="side-h">
        <strong>{title}</strong>
        {sub && <span className="small muted">{sub}</span>}
      </div>
      {items.map((it) => {
        const head = it.group && it.group !== lastGroup ? <div className="side-group">{it.group}</div> : null;
        lastGroup = it.group;
        return (
          <div key={it.href}>
            {head}
            <Link href={it.href} aria-current={isCurrent(it.href) ? 'page' : undefined}>
              {it.label}
              {it.status === 'shell' && <span className="tiny muted" style={{ marginInlineStart: 'auto' }}>à venir</span>}
            </Link>
          </div>
        );
      })}
    </nav>
  );
}
