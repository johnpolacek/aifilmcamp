"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import type React from "react";
import { createContext, useCallback, useContext, useEffect, useMemo, useRef } from "react";

/**
 * Route transitions for the App Router.
 *
 * A page that owns an outro registers it here. A transition-aware Link asks the
 * controller to navigate: the outro plays on the live page, then the router
 * pushes from its completion. Pages without an outro navigate natively.
 * Back and forward never go through here, so they get an intro-only path.
 */

type Finish = () => void;
export type Outro = (finish: Finish) => void;
type NavigateOptions = { replace?: boolean; scroll?: boolean };

type Controller = {
  /** Register the current page's outro. Returns an unregister function. */
  registerOutro: (outro: Outro) => () => void;
  /** Run the registered outro, then push. Returns false when there is nothing to run. */
  navigate: (href: string, options?: NavigateOptions) => boolean;
  /** True once, for the page that mounts after a requested navigation. */
  consumeRequested: () => boolean;
};

const noop: Controller = {
  registerOutro: () => () => {},
  navigate: () => false,
  consumeRequested: () => false,
};

const TransitionContext = createContext<Controller>(noop);

/** How long an outro may hold navigation before the controller pushes anyway. */
const OUTRO_TIMEOUT = 1500;

export function TransitionProvider({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const outroRef = useRef<Outro | null>(null);
  const lockRef = useRef(false);
  const requestedRef = useRef(false);

  // The incoming page consumes the flag in its layout effect, which runs
  // before this one. Whatever is left belongs to a page with no controller.
  // biome-ignore lint/correctness/useExhaustiveDependencies: runs once per route change on purpose
  useEffect(() => {
    requestedRef.current = false;
  }, [pathname]);

  const registerOutro = useCallback((outro: Outro) => {
    outroRef.current = outro;
    return () => {
      if (outroRef.current === outro) outroRef.current = null;
    };
  }, []);

  const navigate = useCallback(
    (href: string, options: NavigateOptions = {}) => {
      const outro = outroRef.current;
      if (!outro) return false;
      // One navigation at a time: the first accepted destination wins.
      if (lockRef.current) return true;
      lockRef.current = true;
      requestedRef.current = true;
      let done = false;
      const finish = () => {
        if (done) return;
        done = true;
        lockRef.current = false;
        if (options.replace) router.replace(href, { scroll: options.scroll });
        else router.push(href, { scroll: options.scroll });
      };
      outro(finish);
      // A stalled timeline (hidden tab, killed tween) must never trap the user.
      window.setTimeout(finish, OUTRO_TIMEOUT);
      return true;
    },
    [router]
  );

  const consumeRequested = useCallback(() => {
    const was = requestedRef.current;
    requestedRef.current = false;
    return was;
  }, []);

  const value = useMemo(
    () => ({ registerOutro, navigate, consumeRequested }),
    [registerOutro, navigate, consumeRequested]
  );

  return <TransitionContext.Provider value={value}>{children}</TransitionContext.Provider>;
}

export function useTransition() {
  return useContext(TransitionContext);
}

type LinkProps = React.ComponentProps<typeof Link>;

function hrefToString(href: LinkProps["href"]): string {
  if (typeof href === "string") return href;
  const { pathname = "", search = "", hash = "", query } = href;
  let q = search;
  if (!q && query && typeof query === "object") {
    const params = new URLSearchParams();
    for (const [k, v] of Object.entries(query)) if (v != null) params.set(k, String(v));
    const s = params.toString();
    q = s ? `?${s}` : "";
  }
  return `${pathname}${q}${hash}`;
}

/**
 * next/link with the page outro in front of it. Prefetching, modified clicks,
 * external URLs, and new tabs behave exactly as with Link: onNavigate only
 * fires for same-origin client navigation.
 */
export function TransitionLink({ onNavigate, replace, scroll, ...props }: LinkProps) {
  const { navigate } = useTransition();

  return (
    <Link
      {...props}
      replace={replace}
      scroll={scroll}
      onNavigate={(e) => {
        let prevented = false;
        onNavigate?.({
          preventDefault: () => {
            prevented = true;
            e.preventDefault();
          },
        });
        if (prevented) return;
        const href = hrefToString(props.href);
        const url = new URL(href, window.location.href);
        const samePage =
          url.pathname === window.location.pathname && url.search === window.location.search;
        // Same-page links (hash jumps, no-ops) stay native.
        if (samePage) return;
        if (navigate(url.pathname + url.search + url.hash, { replace, scroll })) {
          e.preventDefault();
        }
      }}
    />
  );
}
