"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  ArrowDownUp, ArrowRight, ArrowUpRight, Bell, BookOpen, Bookmark, Check, CheckCheck,
  ChevronDown, Clock3, Cloud, ExternalLink,
  Folder, FolderHeart, Image as ImageIcon, LayoutGrid, Link2, LogIn, LogOut,
  Menu, MoreHorizontal, Pin, Plus, Search, Settings2, Share2, ShieldCheck, Shuffle,
  Sparkles, StickyNote, Trash2, Video, X, Zap,
} from "lucide-react";
import { onAuthStateChanged } from "firebase/auth";
import type { User } from "firebase/auth";
import { auth, connectGoogle, db, deleteCloudItem, disconnectGoogle, firebaseReady, saveCloudItem, watchItems } from "@/lib/firebase";
import { formatSavedDate, getDomain, starterSpaces, type ItemType, type MindItem } from "@/lib/items";
import { clearTombstone, loadItems, loadSpaces, loadTombstones, replaceItems, replaceSpaces, setTombstone, type KeepItSpace } from "@/lib/storage";

type View = "everything" | "spaces" | "serendipity" | "profile";
type ToastKind = "success" | "error";
type Toast = { text: string; kind?: ToastKind } | null;
type DesktopUpdate = { version: string; releaseUrl: string };
const filters = ["All", "Reels", "AI", "Coding", "Design", "Productivity", "Articles"];
const sourceIcon = (type: ItemType) => type === "instagramReel" || type === "youtubeVideo" ? <Video size={13} /> : type === "image" ? <ImageIcon size={13} /> : type === "quickNote" || type === "quote" ? <StickyNote size={13} /> : <BookOpen size={13} />;
const sourceName = (type: ItemType) => ({ instagramReel: "Instagram", youtubeVideo: "YouTube", webArticle: "Article", quote: "Quote", image: "Image", quickNote: "Quick note" })[type];
const suggestTags = (text: string) => {
  const words = text.toLowerCase().match(/[a-z0-9+#-]{3,}/g) ?? [];
  const stop = new Set(["this", "that", "with", "from", "your", "about", "have", "what", "when", "where", "will", "into", "https", "www", "com", "article", "saved", "link"]);
  const unique = [...new Set(words.filter((word) => !stop.has(word) && !/^\d+$/.test(word)))];
  return unique.slice(0, 5);
};
const updatedMillis = (item: MindItem) => new Date(item.updatedAt).getTime() || 0;
const mergeByVersion = (...collections: MindItem[][]) => {
  const merged = new Map<string, MindItem>();
  for (const collection of collections) for (const item of collection) {
    const current = merged.get(item.id);
    if (!current || updatedMillis(item) > updatedMillis(current)) merged.set(item.id, item);
  }
  return [...merged.values()];
};

export default function KeepItWeb() {
  const [view, setView] = useState<View>("everything");
  const [items, setItems] = useState<MindItem[]>([]);
  const itemsRef = useRef<MindItem[]>([]);
  itemsRef.current = items;
  const [search, setSearch] = useState("");
  const [tag, setTag] = useState("All");
  const [activeItem, setActiveItem] = useState<MindItem | null>(null);
  const [showComposer, setShowComposer] = useState(false);
  const [saving, setSaving] = useState(false);
  const [composeMode, setComposeMode] = useState<"link" | "note" | "image">("link");
  const [imageDraft, setImageDraft] = useState<File | null>(null);
  const [urlDraft, setUrlDraft] = useState("");
  const [titleDraft, setTitleDraft] = useState("");
  const [noteDraft, setNoteDraft] = useState("");
  const [tagDraft, setTagDraft] = useState("");
  const [toast, setToast] = useState<Toast>(null);
  const [desktopUpdate, setDesktopUpdate] = useState<DesktopUpdate | null>(null);
  const [dismissedDesktopUpdate, setDismissedDesktopUpdate] = useState<string | null>(null);
  const [account, setAccount] = useState<User | null>(null);
  const accountUidRef = useRef<string | null>(null);
  const [authReady, setAuthReady] = useState(!firebaseReady);
  const [syncState, setSyncState] = useState<"local" | "loading" | "synced" | "error">("local");
  const [mobileNav, setMobileNav] = useState(false);
  const [spaces, setSpaces] = useState<KeepItSpace[]>(starterSpaces);
  const [activeSpace, setActiveSpace] = useState<string | null>(null);
  const [sparkId, setSparkId] = useState<string | null>(null);
  const [isReady, setIsReady] = useState(false);
  const [storageScope, setStorageScope] = useState("guest");

  useEffect(() => {
    if (!firebaseReady || !auth) { setAuthReady(true); return; }
    return onAuthStateChanged(auth, (user) => {
      const nextUid = user?.uid ?? null;
      if (accountUidRef.current !== nextUid) { accountUidRef.current = nextUid; setItems([]); setActiveItem(null); setIsReady(false); }
      setAccount(user);
      setAuthReady(true);
    });
  }, []);

  useEffect(() => {
    if (!authReady) return;
    let active = true;
    let stopItems: (() => void) | undefined;
    const scope = account?.uid ?? "guest";
    setIsReady(false);
    setActiveSpace(null);
    setSyncState(account ? "loading" : "local");
    void (async () => {
      try {
        const [storedItems, storedSpaces, storedDeleted, guestItems, guestSpaces, guestDeleted] = await Promise.all([
          loadItems(scope), loadSpaces(scope), loadTombstones(scope),
          account ? loadItems("guest") : Promise.resolve([]),
          account ? loadSpaces("guest") : Promise.resolve(null),
          account ? loadTombstones("guest") : Promise.resolve(new Map<string, number>()),
        ]);
        if (!active) return;
        const localItems = account ? mergeByVersion(storedItems, guestItems) : storedItems;
        const localSpaces = new Map<string, KeepItSpace>();
        for (const space of guestSpaces ?? starterSpaces) localSpaces.set(space.id, space);
        for (const space of storedSpaces ?? []) localSpaces.set(space.id, space);
        const combinedSpaces = [...localSpaces.values()];
        const localDeletes = new Map(guestDeleted);
        for (const [id, timestamp] of storedDeleted) localDeletes.set(id, Math.max(timestamp, localDeletes.get(id) ?? 0));
        setStorageScope(scope);
        setItems(localItems);
        setSpaces(combinedSpaces);
        setIsReady(true);
        if (!account) return;
        stopItems = watchItems(account.uid, (remoteItems, initialSnapshot, remoteDeletes) => {
          if (initialSnapshot) {
            const remoteById = new Map(remoteItems.map((item) => [item.id, item]));
            const remoteDeletedById = new Map(remoteDeletes.map((entry) => [entry.id, entry.updatedAtMs]));
            const merged = new Map(remoteItems.map((item) => [item.id, item]));
            const upload: MindItem[] = [];
            const deleteUpload = new Map<string, number>();
            const latestLocal = mergeByVersion(localItems, itemsRef.current);
            for (const [id, deletedAtMs] of localDeletes) {
              const remote = remoteById.get(id);
              const remoteDelete = remoteDeletedById.get(id) ?? 0;
              const remoteVersion = remote ? updatedMillis(remote) : remoteDelete;
              if (deletedAtMs >= remoteVersion) {
                merged.delete(id);
                deleteUpload.set(id, deletedAtMs);
              } else {
                void clearTombstone(scope, id);
                void clearTombstone("guest", id);
              }
            }
            for (const localItem of latestLocal) {
              const deletedAt = localDeletes.get(localItem.id) ?? 0;
              if (deletedAt >= updatedMillis(localItem)) continue;
              const remoteDelete = remoteDeletedById.get(localItem.id) ?? 0;
              if (remoteDelete >= updatedMillis(localItem)) { merged.delete(localItem.id); continue; }
              const remote = remoteById.get(localItem.id);
              if (!remote || updatedMillis(localItem) > updatedMillis(remote)) {
                merged.set(localItem.id, localItem);
                upload.push(localItem);
                void clearTombstone(scope, localItem.id);
                void clearTombstone("guest", localItem.id);
              }
            }
            const combined = [...merged.values()].sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
            setItems(combined);
            void replaceItems(scope, combined);
            for (const item of upload) void saveCloudItem(account.uid, item).catch(() => setSyncState("error"));
            for (const [id, deletedAtMs] of deleteUpload) {
              void deleteCloudItem(account.uid, id, deletedAtMs).then(() => Promise.all([clearTombstone(scope, id), clearTombstone("guest", id)])).catch(() => setSyncState("error"));
            }
          } else {
            setItems(remoteItems);
          }
          setSyncState("synced");
        }, () => setSyncState("error"));
      } catch {
        if (!active) return;
        setItems([]);
        setSpaces(starterSpaces);
        setStorageScope(scope);
        setIsReady(true);
        setSyncState("error");
      }
    })();
    return () => { active = false; stopItems?.(); };
  }, [authReady, account?.uid]);

  useEffect(() => {
    if (!isReady) return;
    void replaceItems(storageScope, items).catch(() => setSyncState("error"));
  }, [items, isReady, storageScope]);

  useEffect(() => {
    if (!isReady) return;
    void replaceSpaces(storageScope, spaces).catch(() => setSyncState("error"));
  }, [spaces, isReady, storageScope]);

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault(); document.getElementById("global-search")?.focus();
      }
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "n") {
        event.preventDefault(); setShowComposer(true);
      }
      if (event.key === "Escape") { setActiveItem(null); setShowComposer(false); setMobileNav(false); }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  useEffect(() => {
    let active = true;
    void fetch("/api/desktop-update", { cache: "no-store" })
      .then((response) => response.ok ? response.json() : null)
      .then((result) => {
        if (active && result?.updateAvailable === true && typeof result.latestVersion === "string" && typeof result.releaseUrl === "string") {
          setDesktopUpdate({ version: result.latestVersion, releaseUrl: result.releaseUrl });
        }
      })
      .catch(() => { /* Update checks are optional; never block the library. */ });
    return () => { active = false; };
  }, []);

  const notify = useCallback((text: string, kind: ToastKind = "success") => {
    setToast({ text, kind }); window.setTimeout(() => setToast(null), 2800);
  }, []);

  const persist = useCallback(async (item: MindItem) => {
    try { await clearTombstone(storageScope, item.id); } catch { /* The live record still remains usable if local storage is unavailable. */ }
    setItems((current) => current.map((entry) => entry.id === item.id ? item : entry));
    if (account && db) {
      try { await saveCloudItem(account.uid, item); setSyncState("synced"); }
      catch { setSyncState("error"); notify("Could not sync that change. It is still saved on this device.", "error"); }
    }
  }, [account, notify, storageScope]);

  const visibleItems = useMemo(() => items.filter((item) => {
    const query = search.trim().toLowerCase();
    const matchesSearch = !query || [item.title, item.content, item.authorName, item.url, item.tags.join(" ")].some((part) => part?.toLowerCase().includes(query));
    const matchesTag = tag === "All" || (tag === "Reels" ? item.type === "instagramReel" || item.type === "youtubeVideo" : tag === "Articles" ? item.type === "webArticle" : item.tags.some((value) => value.toLowerCase() === tag.toLowerCase()) || item.type.toLowerCase().includes(tag.toLowerCase()));
    if (view === "serendipity" && item.isWatched) return false;
    if (view === "spaces" && activeSpace) {
      const current = spaces.find((space) => space.id === activeSpace);
      return Boolean(current && (item.spaceId === current.id || item.tags.some((value) => current.tags.includes(value.toLowerCase())))) && matchesSearch && matchesTag;
    }
    return matchesSearch && matchesTag;
  }), [items, search, tag, view, activeSpace, spaces]);

  const activeSpark = useMemo(() => {
    const candidates = items.filter((item) => !item.isWatched);
    return candidates.find((item) => item.id === sparkId) ?? candidates[0];
  }, [items, sparkId]);

  const toggleFlag = async (item: MindItem, key: "isWatched" | "isTopMind") => {
    const updated = { ...item, [key]: !item[key], updatedAt: new Date().toISOString() };
    await persist(updated);
    if (activeItem?.id === item.id) setActiveItem(updated);
    notify(key === "isWatched" ? (updated.isWatched ? "Moved to your watched shelf" : "Back in your recall queue") : (updated.isTopMind ? "Pinned to top of mind" : "Unpinned from top of mind"));
  };

  const removeItem = async (item: MindItem) => {
    const deletedAtMs = Date.now();
    try { await setTombstone(storageScope, item.id, deletedAtMs); }
    catch { notify("Could not save this deletion locally.", "error"); return; }
    setItems((current) => current.filter((entry) => entry.id !== item.id));
    setActiveItem(null);
    if (account && db) {
      try { await deleteCloudItem(account.uid, item.id, deletedAtMs); await clearTombstone(storageScope, item.id); setSyncState("synced"); }
      catch { setSyncState("error"); notify("Deleted here; cloud deletion will retry after reconnecting.", "error"); return; }
    }
    notify("Removed from your mind");
  };

  const startCompose = (mode: "link" | "note" | "image" = "link") => {
    setComposeMode(mode); setImageDraft(null); setUrlDraft(""); setTitleDraft(""); setNoteDraft(""); setTagDraft(""); setShowComposer(true);
  };

  const saveDraft = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!isReady || saving) return;
    const cleanInput = urlDraft.trim();
    if (composeMode === "link" && !cleanInput) return;
    if (composeMode === "image" && !imageDraft) { notify("Choose an image to upload first.", "error"); return; }
    const normalizedUrl = composeMode === "link" ? (/^https?:\/\//i.test(cleanInput) ? cleanInput : `https://${cleanInput}`) : undefined;
    if (normalizedUrl) {
      try { const parsed = new URL(normalizedUrl); if (!["http:", "https:"].includes(parsed.protocol) || !parsed.hostname) throw new Error(); }
      catch { notify("Please enter a valid web address.", "error"); return; }
    }
    const normalize = (value: string) => value.toLowerCase().replace(/[?#].*$/, "").replace(/\/$/, "");
    if (normalizedUrl && items.some((item) => item.url && normalize(item.url) === normalize(normalizedUrl))) {
      notify("You already saved that link.", "error");
      return;
    }
    setSaving(true);
    try {
      let metadata: { title?: string; description?: string; image?: string; authorName?: string; siteName?: string; canonicalUrl?: string; type?: ItemType } = {};
      let uploadedImageUrl: string | undefined;
      if (composeMode === "image" && imageDraft) {
        const upload = new FormData();
        upload.append("image", imageDraft);
        const response = await fetch("/api/upload-image", { method: "POST", body: upload });
        const result = await response.json().catch(() => ({})) as { url?: string; error?: string };
        if (!response.ok || !result.url) throw new Error(result.error || "The image could not be uploaded.");
        uploadedImageUrl = result.url;
      }
      if (normalizedUrl) {
        try {
          const response = await fetch(`/api/metadata?url=${encodeURIComponent(normalizedUrl)}`);
          if (response.ok) metadata = await response.json();
        } catch { /* Saving still works without a page preview. */ }
      }
      const timestamp = new Date().toISOString();
      const imageTitle = imageDraft?.name.replace(/\.[^.]+$/, "").trim() || "Saved image";
      const cleanTitle = titleDraft.trim() || metadata.title || (composeMode === "note" ? "Untitled note" : composeMode === "image" ? imageTitle : getDomain(normalizedUrl));
      const description = noteDraft.trim() || metadata.description;
      const parsedTags = tagDraft.split(",").map((value) => value.trim().replace(/^#/, "")).filter(Boolean);
      const inferredTags = parsedTags.length ? parsedTags : suggestTags(`${cleanTitle} ${description ?? ""} ${getDomain(normalizedUrl)}`);
      const item: MindItem = {
        id: typeof crypto !== "undefined" && "randomUUID" in crypto ? crypto.randomUUID() : `web-${Date.now()}`,
        title: cleanTitle,
        ...(uploadedImageUrl ? { url: uploadedImageUrl, thumbnailUrl: uploadedImageUrl } : normalizedUrl ? { url: metadata.canonicalUrl || normalizedUrl } : {}),
        ...(!uploadedImageUrl && metadata.image ? { thumbnailUrl: metadata.image } : {}),
        ...(description ? { content: description } : {}),
        authorName: composeMode === "image" ? "Image upload" : composeMode === "note" ? "Quick note" : (metadata.authorName || metadata.siteName || getDomain(normalizedUrl) || "Saved link"),
        type: composeMode === "image" ? "image" : composeMode === "note" ? "quickNote" : (metadata.type ?? "webArticle"),
        tags: inferredTags,
        isWatched: false,
        isTopMind: false,
        createdAt: timestamp,
        updatedAt: timestamp,
      };
      setItems((current) => [item, ...current]);
      setShowComposer(false);
      setImageDraft(null);
      notify(composeMode === "note" ? "Note saved on this device" : composeMode === "image" ? "Image saved to your KeepIt library" : "Link saved on this device");
      if (account && db) {
        try { await saveCloudItem(account.uid, item); setSyncState("synced"); notify("Saved and synced across your devices"); }
        catch { setSyncState("error"); notify("Saved on this device; cloud sync will retry when available.", "error"); }
      }
    } catch (error) {
      notify(error instanceof Error ? error.message : "Could not save this item.", "error");
    } finally { setSaving(false); }
  };

  const signIn = async () => {
    if (!firebaseReady) { notify("Add Firebase web settings to .env.local to enable cloud sync.", "error"); return; }
    try { await connectGoogle(); notify("Google account connected"); }
    catch (error) { notify(error instanceof Error ? error.message : "Could not connect Google account.", "error"); }
  };

  const addSpace = () => {
    const name = window.prompt("Name your new Space");
    if (!name?.trim()) return;
    const id = `space-${Date.now()}`;
    const colors = ["#EF8F6B", "#78A68F", "#8B8ED9", "#D5A653", "#D7799E"];
    setSpaces((current) => [...current, { id, name: name.trim(), subtitle: "Your own little corner", color: colors[current.length % colors.length], icon: "folder", tags: [] }]);
    setActiveSpace(id); notify("Space created");
  };

  const exportData = () => {
    const blob = new Blob([JSON.stringify({ format: "keepit-export-v1", items, spaces, exportedAt: new Date().toISOString() }, null, 2)], { type: "application/json" });
    const anchor = document.createElement("a"); anchor.href = URL.createObjectURL(blob); anchor.download = "keepit-export.json"; anchor.click(); URL.revokeObjectURL(anchor.href);
    notify("Your KeepIt export is ready");
  };

  const heading = view === "everything" ? "Everything" : view === "spaces" ? (activeSpace ? spaces.find((space) => space.id === activeSpace)?.name ?? "Spaces" : "Your spaces") : view === "serendipity" ? "Serendipity" : "Your profile";
  const helper = view === "everything" ? "A little home for everything worth keeping." : view === "spaces" ? "Thoughtfully collected, easy to find again." : view === "serendipity" ? "A forgotten gem, right when you need it." : "Your private corner of the internet.";

  return (
    <div className="app-shell">
      <aside className={`sidebar ${mobileNav ? "sidebar-open" : ""}`}>
        <button className="brand" onClick={() => { setView("everything"); setMobileNav(false); }} aria-label="KeepIt home">
          <span className="brand-mark app-logo"><img src="/keepit-icon.png" alt="" width={42} height={42} /></span><span className="brand-copy"><strong>KeepIt</strong><small>YOUR VISUAL SECOND BRAIN</small></span>
        </button>
        <button className="quick-save" onClick={() => startCompose("link")}><span><Plus size={18} strokeWidth={2.4} /></span>Quick save <kbd>⌘ N</kbd></button>
        <div className="side-label">LIBRARY</div>
        <nav className="main-nav" aria-label="Main navigation">
          <button className={view === "everything" ? "nav-item active" : "nav-item"} onClick={() => { setView("everything"); setActiveSpace(null); setMobileNav(false); }}><LayoutGrid size={17} /><span>Everything</span><b className="nav-count">{items.length}</b></button>
          <button className={view === "spaces" ? "nav-item active" : "nav-item"} onClick={() => { setView("spaces"); setActiveSpace(null); setMobileNav(false); }}><Folder size={17} /><span>Spaces</span><b className="nav-count">{spaces.length}</b></button>
          <button className={view === "serendipity" ? "nav-item active" : "nav-item"} onClick={() => { setView("serendipity"); setActiveSpace(null); setMobileNav(false); }}><Sparkles size={17} /><span>Serendipity</span><span className="nav-dot" /></button>
        </nav>
        <div className="side-label spaces-label"><span>YOUR SPACES</span><button onClick={addSpace} aria-label="Add a space"><Plus size={15} /></button></div>
        <div className="space-nav">
          {spaces.slice(0, 5).map((space) => <button key={space.id} className={activeSpace === space.id ? "space-nav-item selected" : "space-nav-item"} onClick={() => { setView("spaces"); setActiveSpace(space.id); setMobileNav(false); }}><span className="space-color" style={{ background: space.color }} /><span>{space.name}</span></button>)}
        </div>
        <div className="sidebar-bottom">
          <div className="sync-card"><div className="sync-icon"><Cloud size={16} /></div><div><strong>{account ? "Cloud connected" : "Private on this device"}</strong><small>{account ? (syncState === "loading" ? "Syncing your library…" : syncState === "error" ? "Sync needs attention" : "Saved across your devices") : "Saved in this browser · offline ready"}</small></div><span className={`sync-status ${syncState}`} /></div>
          <button className={view === "profile" ? "profile-link active" : "profile-link"} onClick={() => { setView("profile"); setMobileNav(false); }}><span className="avatar">{account?.displayName?.slice(0, 1).toUpperCase() ?? "K"}</span><span className="profile-copy"><strong>{account?.displayName ?? "Your library"}</strong><small>{account?.email ?? "This browser"}</small></span><MoreHorizontal size={18} /></button>
        </div>
      </aside>
      {mobileNav && <button className="mobile-scrim" aria-label="Close navigation" onClick={() => setMobileNav(false)} />}

      <main className="main-area">
        {desktopUpdate && dismissedDesktopUpdate !== desktopUpdate.version && <div className="desktop-update-banner" role="status">
          <div className="desktop-update-copy"><strong>KeepIt Desktop {desktopUpdate.version} is ready</strong><span>Download the latest version to get the newest improvements.</span></div>
          <a className="desktop-update-link" href={desktopUpdate.releaseUrl} target="_blank" rel="noreferrer">View update <ExternalLink size={14} /></a>
          <button className="desktop-update-dismiss" type="button" aria-label="Dismiss update notice" onClick={() => setDismissedDesktopUpdate(desktopUpdate.version)}><X size={16} /></button>
        </div>}
        <header className="topbar">
          <button className="mobile-menu icon-button" onClick={() => setMobileNav(true)} aria-label="Open navigation"><Menu size={20} /></button>
          <div className="breadcrumbs"><span>My mind</span><span className="crumb-slash">/</span><strong>{heading}</strong></div>
          <div className="top-actions">
            <label className="search-box" htmlFor="global-search"><Search size={16} /><input id="global-search" placeholder="Search your mind..." value={search} onChange={(event) => setSearch(event.target.value)} /><kbd>⌘ K</kbd></label>
            <button className="icon-button notification-button" aria-label="Notifications" onClick={() => notify("You're all caught up") }><span className="notification-ping" /><Bell size={17} /></button>
            <button className="top-avatar" onClick={() => setView("profile")} aria-label="Open profile">{account?.displayName?.slice(0, 1).toUpperCase() ?? "K"}</button>
          </div>
        </header>

        <div className="page-content">
          <div className="page-intro">
            <div><div className="eyebrow"><span className="eyebrow-spark">✳</span> YOUR PERSONAL ARCHIVE</div><h1>{heading}<span className="title-period">.</span></h1><p>{helper}</p></div>
            {view !== "profile" && <button className="primary-button" onClick={() => startCompose("link")}><Plus size={17} /> Save something <span className="button-shortcut">⌘ N</span></button>}
          </div>

            {view === "everything" && <>
            <section className="welcome-hero">
              <div className="welcome-hero-scrim" />
              <div className="welcome-hero-copy">
                <span className="welcome-eyebrow"><span className="welcome-star">✦</span> KEEP YOUR CURIOSITY CLOSE</span>
                <h2>Collect less.<br/><em>Remember more.</em></h2>
                <p>A considered home for all the little things<br className="desktop-break"/> you’ll be glad you kept.</p>
                <div className="welcome-actions"><button onClick={() => startCompose("link")}><Plus size={15}/> Capture an idea</button><span><ShieldCheck size={13}/> Private by default</span></div>
              </div>
              <div className="welcome-hero-seal"><span className="seal-top">YOUR SECOND BRAIN</span><span className="seal-count">{String(items.length).padStart(2, "0")}</span><span className="seal-bottom">IDEAS KEPT</span><span className="seal-orbit"/></div>
              <span className="welcome-hero-footnote">A calmer kind of collecting <i>✳</i></span>
            </section>
            <section className="insight-strip" aria-label="Library highlights">
              <div className="insight-cell"><div className="insight-icon peach"><Bookmark size={16} /></div><div><strong>{items.length} <small>saved</small></strong><span>Ideas worth keeping</span></div></div>
              <div className="insight-divider" />
              <div className="insight-cell"><div className="insight-icon lavender"><Sparkles size={16} /></div><div><strong>{items.filter((item) => !item.isWatched).length} <small>to revisit</small></strong><span>Waiting for the right moment</span></div></div>
              <div className="insight-divider" />
              <div className="insight-cell"><div className="insight-icon mint"><CheckCheck size={16} /></div><div><strong>{items.filter((item) => item.isWatched).length} <small>rediscovered</small></strong><span>Your mind is getting lighter</span></div></div>
              <div className="insight-aside"><span className="tiny-sun">☼</span> Little by little, ideas find their place.</div>
            </section>
            <div className="feed-toolbar"><div className="filter-row" role="tablist" aria-label="Filter saved items">{filters.map((filter) => <button key={filter} role="tab" aria-selected={tag === filter} className={tag === filter ? "filter-pill selected" : "filter-pill"} onClick={() => setTag(filter)}>{filter === "All" && <span className="all-filter-dot" />}{filter}</button>)}</div><button className="sort-button" onClick={() => setItems((current) => [...current].reverse())}><ArrowDownUp size={14} /> Recently saved <ChevronDown size={13} /></button></div>
            <div className="feed-subtitle"><span>{search || tag !== "All" ? `${visibleItems.length} matching ideas` : "A home for everything worth keeping"}</span><button onClick={() => startCompose("note")}><StickyNote size={14} /> Write a thought</button></div>
            {visibleItems.length > 0 ? <div className="masonry-grid">{visibleItems.map((item, index) => <MemoryCard key={item.id} item={item} onClick={() => setActiveItem(item)} onTogglePin={() => void toggleFlag(item, "isTopMind")} index={index} />)}</div> : (search || tag !== "All") ? <NoResults onReset={() => { setSearch(""); setTag("All"); }} /> : <EmptyState onSave={() => startCompose("link")} onNote={() => startCompose("note")} onSpace={addSpace} />}
          </>}

          {view === "spaces" && <>
            {!activeSpace && <div className="space-grid">{spaces.map((space, index) => {
              const count = items.filter((item) => item.spaceId === space.id || item.tags.some((value) => space.tags.includes(value.toLowerCase()))).length;
              return <button key={space.id} className={`space-card space-card-${index % 5}`} onClick={() => setActiveSpace(space.id)}><div className="space-card-top"><span className="space-card-icon" style={{ color: space.color, background: `${space.color}18` }}>{space.icon === "play" ? <Video size={22} /> : space.icon === "book" ? <BookOpen size={22} /> : space.icon === "palette" ? <ImageIcon size={22} /> : space.icon === "sun" ? <Zap size={22} /> : <Sparkles size={22} />}</span><MoreHorizontal size={19} /></div><div className="space-card-art" style={{ "--space-color": space.color } as React.CSSProperties}><span className="art-orb one" /><span className="art-orb two" /><span className="art-lines">✳</span><span className="art-count">{count} {count === 1 ? "idea" : "ideas"}</span></div><div className="space-card-copy"><strong>{space.name}</strong><span>{space.subtitle}</span></div></button>;
            })}<button className="new-space-card" onClick={addSpace}><span className="new-space-plus"><Plus size={21} /></span><strong>Create a space</strong><span>Give your ideas a new home</span></button></div>}
            {activeSpace && <><button className="back-link" onClick={() => setActiveSpace(null)}><ArrowRight size={14} className="back-arrow" /> All spaces</button><div className="space-detail-banner"><div className="space-detail-orb" style={{ background: spaces.find((space) => space.id === activeSpace)?.color }} /><div><span className="eyebrow">A PLACE FOR WHAT MATTERS</span><h2>{spaces.find((space) => space.id === activeSpace)?.name}</h2><p>{spaces.find((space) => space.id === activeSpace)?.subtitle}</p></div></div><div className="masonry-grid">{visibleItems.map((item, index) => <MemoryCard key={item.id} item={item} onClick={() => setActiveItem(item)} onTogglePin={() => void toggleFlag(item, "isTopMind")} index={index} />)}</div>{visibleItems.length === 0 && <EmptyState onSave={() => startCompose("link")} onNote={() => startCompose("note")} onSpace={addSpace} />}</>}
          </>}

          {view === "serendipity" && <Serendipity items={items} spark={activeSpark} onShuffle={() => { const candidates = items.filter((item) => !item.isWatched); if (candidates.length > 1) { const next = candidates[Math.floor(Math.random() * candidates.length)]; setSparkId(next.id === activeSpark?.id ? candidates[(candidates.indexOf(next) + 1) % candidates.length].id : next.id); } }} onOpen={(item) => setActiveItem(item)} onWatched={() => activeSpark && void toggleFlag(activeSpark, "isWatched")} />}

          {view === "profile" && <Profile account={account} syncState={syncState} ready={firebaseReady} onSignIn={signIn} onSignOut={() => void disconnectGoogle()} onExport={exportData} count={items.length} />}
          <footer className="page-footer"><span><span className="footer-heart">♥</span> Made for the things you don’t want to lose.</span><span className="footer-right"><ShieldCheck size={13} /> Private by default <span className="footer-dot">·</span> KeepIt Web</span></footer>
        </div>
      </main>

      {activeItem && <ItemDetail item={activeItem} spaces={spaces} onClose={() => setActiveItem(null)} onUpdate={(updated) => { void persist(updated); setActiveItem(updated); }} onDelete={() => void removeItem(activeItem)} onToggleWatched={() => void toggleFlag(activeItem, "isWatched")} onTogglePin={() => void toggleFlag(activeItem, "isTopMind")} />}
      {showComposer && <Composer mode={composeMode} setMode={setComposeMode} title={titleDraft} setTitle={setTitleDraft} url={urlDraft} setUrl={setUrlDraft} note={noteDraft} setNote={setNoteDraft} tags={tagDraft} setTags={setTagDraft} image={imageDraft} setImage={setImageDraft} saving={saving} onClose={() => { setShowComposer(false); setImageDraft(null); }} onSubmit={saveDraft} />}
      {toast && <div className={`toast ${toast.kind ?? ""}`}><span className="toast-check">{toast.kind === "error" ? "!" : "✓"}</span>{toast.text}<button onClick={() => setToast(null)} aria-label="Dismiss"><X size={14} /></button></div>}
    </div>
  );
}

function MemoryCard({ item, onClick, onTogglePin, index }: { item: MindItem; onClick: () => void; onTogglePin: () => void; index: number }) {
  const imageHeight = [226, 184, 248, 198, 212, 176, 230, 194][index % 8];
  return <article className={`memory-card ${item.isTopMind ? "pinned" : ""}`}>
    {item.thumbnailUrl && <button className="memory-image-wrap" onClick={onClick} aria-label={`Open ${item.title}`} style={{ height: imageHeight }}><img src={item.thumbnailUrl} alt="" className="memory-image"/><span className="image-shade"/><span className="source-chip">{sourceIcon(item.type)} {sourceName(item.type)}</span>{(item.type === "instagramReel" || item.type === "youtubeVideo") && <span className="play-button"><span>▶</span></span>}{item.isWatched && <span className="watched-chip"><Check size={11} /> Revisited</span>}<span className="image-action" onClick={(event) => { event.stopPropagation(); onTogglePin(); }} title={item.isTopMind ? "Unpin" : "Pin to top of mind"}><Pin size={14} fill={item.isTopMind ? "currentColor" : "none"} /></span></button>}
    <button className="memory-content" onClick={onClick}><div className="memory-meta"><span className="memory-domain">{getDomain(item.url)}</span><span className="meta-dot">·</span><span>{formatSavedDate(item.createdAt)}</span></div><h3>{item.title}</h3>{item.content && <p>{item.content}</p>}{item.tags.length > 0 && <div className="tag-list">{item.tags.slice(0, 3).map((value) => <span className="tag-chip" key={value}>#{value}</span>)}</div>}<div className="card-footer"><span className="author-dot" />{item.authorName ?? "Saved to your mind"}<span className="card-footer-action"><ArrowUpRight size={14} /></span></div></button>
  </article>;
}

function EmptyState({ onSave, onNote, onSpace }: { onSave: () => void; onNote: () => void; onSpace: () => void }) {
  return <section className="empty-state">
    <div className="empty-copy">
      <span className="empty-overline"><span>✳</span> A FRESH PAGE</span>
      <h2>Your mind is ready<br/><em>for something good.</em></h2>
      <p>Keep a link, a little thought, a spark you don’t want to lose. You can sort it out later.</p>
      <div className="empty-actions"><button className="empty-primary" onClick={onSave}><Link2 size={15}/> Save your first link <span>⌘ N</span></button><button className="empty-secondary" onClick={onNote}><StickyNote size={15}/> Write a quick note</button></div>
      <div className="empty-assurance"><ShieldCheck size={14}/> Your collection starts private, right here on this device.</div>
    </div>
    <div className="empty-art">
      <span className="empty-orbit orbit-a"/><span className="empty-orbit orbit-b"/>
      <div className="empty-orb"><img src="/keepit-icon.png" alt="" width={42} height={42} /></div>
      <div className="empty-note-card"><span>01 <i>/</i> CAPTURE</span><strong>A thought is a good place to start.</strong><div className="note-lines"><i/><i/><i/></div><small>KEEPIT · YOUR SECOND BRAIN</small></div>
      <div className="empty-art-caption">A GOOD COLLECTION<br/><em>BEGINS WITH ONE THING</em></div>
      <button className="empty-space-link" onClick={onSpace}><Folder size={13}/> Or start with a Space <ArrowUpRight size={12}/></button>
      <span className="empty-art-spark spark-one">✳</span><span className="empty-art-spark spark-two">✦</span>
    </div>
  </section>;
}

function NoResults({ onReset }: { onReset: () => void }) { return <section className="no-results"><div className="no-results-icon"><Search size={18}/></div><div><strong>No matching ideas this time.</strong><p>Try another word or clear the filters to see your whole collection.</p></div><button onClick={onReset}>Clear filters <X size={13}/></button></section>; }

function Serendipity({ items, spark, onShuffle, onOpen, onWatched }: { items: MindItem[]; spark?: MindItem; onShuffle: () => void; onOpen: (item: MindItem) => void; onWatched: () => void }) {
  const queue = items.filter((item) => !item.isWatched);
  if (!spark) return <div className="all-caught-up"><div><CheckCheck size={34} /></div><h2>{items.length ? "Your mind is up to date." : "Nothing to rediscover yet."}</h2><p>{items.length ? "You’ve revisited everything on your shelf. Save a new spark for later." : "Save a link, image or quick note and it will find its way back to you here."}</p></div>;
  const days = Math.max(0, Math.floor((Date.now() - new Date(spark.createdAt).getTime()) / 86_400_000));
  return <div className="serendipity-layout"><section className="spark-main"><div className="spark-heading"><div><span className="eyebrow"><Sparkles size={13} /> DAILY RECALL SPARK</span><h2>A forgotten gem, resurfaced.</h2><p>A small nudge back to something you once thought was worth keeping.</p></div><button className="shuffle-button" onClick={onShuffle}><Shuffle size={15} /> Shuffle</button></div><button className="featured-memory" onClick={() => onOpen(spark)}><div className="featured-photo" style={{ backgroundImage: spark.thumbnailUrl ? `url('${spark.thumbnailUrl}')` : "radial-gradient(circle at 78% 24%, #f6c3a9 0, transparent 31%), linear-gradient(135deg, #f5e7dc, #e6e3f3 58%, #dcefe5)" }}><span className="saved-ago"><Clock3 size={13} /> {days === 0 ? "Saved today" : days === 1 ? "Saved yesterday" : `Saved ${days} days ago`}</span><span className="featured-open"><ArrowUpRight size={17} /></span><span className="feature-glow" /></div><div className="featured-copy"><div className="memory-meta"><span className="memory-domain">{getDomain(spark.url)}</span><span className="meta-dot">·</span>{formatSavedDate(spark.createdAt)}</div><h3>{spark.title}</h3><p>{spark.content}</p><div className="feature-actions"><span className="mark-watched" onClick={(event) => { event.stopPropagation(); onWatched(); }}><CheckCheck size={16} /> I’ve revisited this</span><span className="quiet-link"><ExternalLink size={15} /> Open original</span></div></div></button></section><aside className="recall-queue"><div className="queue-header"><div><span className="eyebrow">YOUR RECALL QUEUE</span><h3>Still waiting for you <span>{queue.length}</span></h3></div><button aria-label="Shuffle memory" onClick={onShuffle}><Shuffle size={15} /></button></div><div className="queue-list">{queue.slice(0, 5).map((item, index) => <button className={`queue-item ${item.id === spark.id ? "current" : ""}`} key={item.id} onClick={() => onOpen(item)}><span className="queue-thumb">{item.thumbnailUrl ? <img src={item.thumbnailUrl} alt="" /> : <StickyNote size={18} />}</span><span className="queue-text"><strong>{item.title}</strong><small>{item.authorName ?? getDomain(item.url)} <span>·</span> {formatSavedDate(item.createdAt)}</small></span><span className="queue-number">0{index + 1}</span></button>)}</div><div className="queue-note"><span>✦</span> The best ideas are worth meeting twice.</div></aside></div>;
}

function Profile({ account, syncState, ready, onSignIn, onSignOut, onExport, count }: { account: User | null; syncState: string; ready: boolean; onSignIn: () => void; onSignOut: () => void; onExport: () => void; count: number }) {
  return <div className="profile-layout"><section className="profile-hero"><div className="profile-cover"><div className="cover-orb cover-one"/><div className="cover-orb cover-two"/><span className="cover-label">A LITTLE SPACE FOR BIG IDEAS</span><div className="cover-stars">✳ <span>✧</span> ✦</div></div><div className="profile-info"><div className="profile-large-avatar">{account?.displayName?.slice(0, 1).toUpperCase() ?? "K"}</div><div className="profile-info-copy"><h2>{account?.displayName ?? "Your library"}</h2><p>{account?.email ?? "Saved on this browser"}</p></div>{account ? <button className="secondary-button" onClick={onSignOut}><LogOut size={15} /> Disconnect</button> : <button className="primary-button" onClick={onSignIn}>{ready ? <LogIn size={15} /> : <Cloud size={15} />} {ready ? "Connect Google" : "Set up cloud sync"}</button>}</div></section><section className="profile-stat-grid"><div className="profile-stat"><span className="stat-icon coral"><Bookmark size={17}/></span><strong>{count}</strong><small>Saved ideas</small></div><div className="profile-stat"><span className="stat-icon violet"><FolderHeart size={17}/></span><strong>{starterSpaces.length}</strong><small>Spaces to explore</small></div><div className="profile-stat"><span className="stat-icon green"><CheckCheck size={17}/></span><strong>Local-first</strong><small>Your ideas stay yours</small></div></section><section className="settings-card"><div className="settings-heading"><div><span className="eyebrow">YOUR PREFERENCES</span><h3>KeepIt, your way.</h3></div><Settings2 size={19}/></div><button className="setting-row" onClick={onExport}><span className="setting-icon"><Share2 size={16}/></span><span><strong>Export your mind</strong><small>Download a portable JSON copy of your saved ideas.</small></span><ArrowRight size={16}/></button><div className="setting-row setting-static"><span className="setting-icon"><Cloud size={16}/></span><span><strong>Cloud sync</strong><small>{account ? `Connected · ${syncState}` : ready ? "Optional · authorize this site in Firebase, then sign in to sync with mobile." : "Set Firebase web config to connect your mobile library."}</small></span><span className={`settings-status ${account ? "online" : "offline"}`}>{account ? "ON" : "LOCAL"}</span></div><div className="privacy-note"><ShieldCheck size={16}/><span><strong>Private by default.</strong> Your saved ideas belong to you. No feed, no noise, just your mind.</span></div></section></div>;
}

function ItemDetail({ item, spaces, onClose, onUpdate, onDelete, onToggleWatched, onTogglePin }: { item: MindItem; spaces: typeof starterSpaces; onClose: () => void; onUpdate: (item: MindItem) => void; onDelete: () => void; onToggleWatched: () => void; onTogglePin: () => void }) {
  const [title, setTitle] = useState(item.title);
  const [content, setContent] = useState(item.content ?? "");
  const [tagText, setTagText] = useState(item.tags.join(", "));
  const saveEdits = () => onUpdate({ ...item, title: title.trim() || "Untitled", content: content.trim() || undefined, tags: tagText.split(",").map((value) => value.trim().replace(/^#/, "")).filter(Boolean), updatedAt: new Date().toISOString() });
  return <div className="modal-backdrop detail-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}><section className="detail-panel" role="dialog" aria-modal="true" aria-label="Saved item details"><div className="detail-top"><span className="detail-kind">{sourceIcon(item.type)} {sourceName(item.type)}</span><div className="detail-top-actions"><button className={item.isTopMind ? "mini-action pinned-action" : "mini-action"} onClick={onTogglePin} title="Pin to top of mind"><Pin size={16}/></button><button className="mini-action" onClick={onClose} aria-label="Close"><X size={18}/></button></div></div>{item.thumbnailUrl && <div className="detail-image"><img src={item.thumbnailUrl} alt=""/><span className="detail-domain">{getDomain(item.url)}</span></div>}<div className="detail-content"><div className="detail-saved"><span className="author-dot"/> SAVED {formatSavedDate(item.createdAt).toUpperCase()} <span>·</span> {item.authorName ?? "YOUR LIBRARY"}</div><label className="field-label" htmlFor="edit-title">TITLE</label><input id="edit-title" className="detail-title-input" value={title} onChange={(event) => setTitle(event.target.value)} onBlur={saveEdits}/><label className="field-label" htmlFor="edit-note">YOUR NOTE</label><textarea id="edit-note" className="detail-note-input" value={content} onChange={(event) => setContent(event.target.value)} onBlur={saveEdits} placeholder="Add a thought to remember why this mattered…" rows={4}/><label className="field-label" htmlFor="edit-tags">TAGS <span>Separate with commas</span></label><input id="edit-tags" className="edit-tags-input" value={tagText} onChange={(event) => setTagText(event.target.value)} onBlur={saveEdits}/><div className="detail-tags">{item.tags.map((value) => <span className="tag-chip" key={value}>#{value}</span>)}</div>{item.url && <a className="original-link" href={item.url} target="_blank" rel="noreferrer"><Link2 size={15}/><span>{getDomain(item.url)}</span><ExternalLink size={14}/></a>}<div className="detail-actions"><button className={item.isWatched ? "watched-button done" : "watched-button"} onClick={onToggleWatched}>{item.isWatched ? <CheckCheck size={16}/> : <Check size={16}/>} {item.isWatched ? "Revisited" : "Mark as revisited"}</button><button className="delete-action" onClick={onDelete}><Trash2 size={15}/></button></div><div className="detail-space-row"><span>KEEP IN A SPACE</span><select value={item.spaceId ?? ""} onChange={(event) => onUpdate({ ...item, spaceId: event.target.value || undefined, updatedAt: new Date().toISOString() })}><option value="">No space yet</option>{spaces.map((space) => <option key={space.id} value={space.id}>{space.name}</option>)}</select></div></div></section></div>;
}

function Composer({ mode, setMode, title, setTitle, url, setUrl, note, setNote, tags, setTags, image, setImage, saving, onClose, onSubmit }: {
  mode: "link" | "note" | "image";
  setMode: (mode: "link" | "note" | "image") => void;
  title: string;
  setTitle: (value: string) => void;
  url: string;
  setUrl: (value: string) => void;
  note: string;
  setNote: (value: string) => void;
  tags: string;
  setTags: (value: string) => void;
  image: File | null;
  setImage: (value: File | null) => void;
  saving: boolean;
  onClose: () => void;
  onSubmit: (event: React.FormEvent<HTMLFormElement>) => void;
}) {
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const [fileMessage, setFileMessage] = useState("");
  useEffect(() => {
    if (!image) { setImagePreview(null); return; }
    const previewUrl = URL.createObjectURL(image);
    setImagePreview(previewUrl);
    return () => URL.revokeObjectURL(previewUrl);
  }, [image]);
  const chooseImage = (event: React.ChangeEvent<HTMLInputElement>) => {
    const selected = event.target.files?.[0] ?? null;
    event.target.value = "";
    if (!selected) return;
    if (!["image/jpeg", "image/png", "image/webp", "image/gif"].includes(selected.type)) {
      setImage(null); setFileMessage("Choose a JPEG, PNG, WebP or GIF image."); return;
    }
    if (selected.size > 4 * 1024 * 1024) {
      setImage(null); setFileMessage("That image is over 4 MB. Choose a smaller file."); return;
    }
    setFileMessage(""); setImage(selected);
  };
  return <div className="modal-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}><form className="composer-modal" onSubmit={onSubmit} role="dialog" aria-modal="true" aria-label="Save to KeepIt">
    <div className="composer-head"><div><span className="eyebrow">KEEP THE GOOD STUFF</span><h2>Save to your mind<span className="title-period">.</span></h2></div><button type="button" className="mini-action" onClick={onClose} aria-label="Close"><X size={19}/></button></div>
    <div className="composer-tabs" role="tablist" aria-label="Choose what to save">
      <button type="button" role="tab" aria-selected={mode === "link"} className={mode === "link" ? "composer-tab active" : "composer-tab"} onClick={() => setMode("link")}><Link2 size={15}/> Save a link</button>
      <button type="button" role="tab" aria-selected={mode === "note"} className={mode === "note" ? "composer-tab active" : "composer-tab"} onClick={() => setMode("note")}><StickyNote size={15}/> Quick note</button>
      <button type="button" role="tab" aria-selected={mode === "image"} className={mode === "image" ? "composer-tab active" : "composer-tab"} onClick={() => setMode("image")}><ImageIcon size={15}/> Image</button>
    </div>
    {mode === "link" && <label className="composer-field"><span>LINK TO KEEP</span><div className="input-with-icon"><Link2 size={16}/><input autoFocus placeholder="Paste a URL — article, reel, video..." value={url} onChange={(event) => setUrl(event.target.value)} required/></div></label>}
    {mode === "image" && <div className="composer-field"><span>IMAGE TO KEEP <small>JPEG, PNG, WebP or GIF · up to 4 MB</small></span><label className="image-pick-zone">{imagePreview ? <span className="image-pick-preview"><img src={imagePreview} alt="Selected image preview"/><span><strong>{image?.name}</strong><small>Click to choose a different image</small></span></span> : <span className="image-pick-placeholder"><span><ImageIcon size={21}/></span><strong>Choose an image</strong><small>Browse this device · up to 4 MB</small></span>}<input className="image-file-input" type="file" accept="image/jpeg,image/png,image/webp,image/gif" onChange={chooseImage} aria-label="Choose an image to upload"/></label>{fileMessage && <small className="image-file-message">{fileMessage}</small>}</div>}
    <label className="composer-field"><span>{mode === "note" ? "GIVE YOUR THOUGHT A TITLE" : "A TITLE FOR LATER (OPTIONAL)"}</span><input autoFocus={mode === "note"} placeholder={mode === "note" ? "A thought worth keeping" : mode === "image" ? "Name this image" : "Let KeepIt find a name for now"} value={title} onChange={(event) => setTitle(event.target.value)} /></label>
    <label className="composer-field"><span>A NOTE TO YOUR FUTURE SELF <small>OPTIONAL</small></span><textarea rows={3} placeholder="Why did this catch your eye?" value={note} onChange={(event) => setNote(event.target.value)} /></label>
    <label className="composer-field"><span>ADD SOME TAGS <small>OPTIONAL</small></span><input placeholder="design, ideas, read-later" value={tags} onChange={(event) => setTags(event.target.value)} /></label>
    <div className="composer-foot"><span>{mode === "image" ? <><ImageIcon size={14}/> Uploaded to ImgBB · image URL is public</> : <><ShieldCheck size={14}/> Saved privately in this browser{firebaseReady ? " · sign in to sync" : ""}</>}</span><button className="primary-button" type="submit" disabled={saving || (mode === "image" && !image)}><Plus size={16}/> {saving ? (mode === "image" ? "Uploading…" : "Saving…") : mode === "image" ? "Upload & save" : "Save it"}</button></div>
  </form></div>;
}
