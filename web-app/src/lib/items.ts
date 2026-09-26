export type ItemType = "instagramReel" | "youtubeVideo" | "webArticle" | "quote" | "image" | "quickNote";

export type MindItem = {
  id: string;
  title: string;
  url?: string;
  content?: string;
  thumbnailUrl?: string;
  authorName?: string;
  authorAvatar?: string;
  type: ItemType;
  tags: string[];
  spaceId?: string;
  isWatched: boolean;
  isTopMind: boolean;
  dominantColorHex?: string;
  createdAt: string;
  updatedAt: string;
};

// These are built-in smart collections, not pre-populated user data. Their tag rules
// mirror the categories in flutter_app/lib/presentation/screens/spaces_screen.dart.
export const starterSpaces = [
  { id: "ai-tech", name: "AI & Tech Stack", subtitle: "Tools, systems & ideas", color: "#6D8CF7", icon: "sparkles", tags: ["ai", "tech", "coding", "dev", "tools", "architecture"] },
  { id: "reels", name: "Reels & videos", subtitle: "A watch-later shelf", color: "#E879A9", icon: "play", tags: ["reel", "video", "shorts"] },
  { id: "design", name: "Design & aesthetic", subtitle: "Visual fuel for later", color: "#9B81E8", icon: "palette", tags: ["design", "visual", "photo", "palette", "cinematic"] },
  { id: "reading", name: "Deep reading list", subtitle: "Articles worth your time", color: "#55A98B", icon: "book", tags: ["article", "reading", "guide", "read"] },
  { id: "life", name: "Productivity & life", subtitle: "Small things that help", color: "#E8AA55", icon: "sun", tags: ["productivity", "useful", "habits", "mindset"] },
];

export const formatSavedDate = (value: string) => new Intl.DateTimeFormat("en", { month: "short", day: "numeric" }).format(new Date(value));
export const getDomain = (url?: string) => {
  if (!url) return "A note";
  try { return new URL(url).hostname.replace(/^www\./, ""); } catch { return "Saved link"; }
};
export const getTypeLabel = (type: ItemType) => ({ instagramReel: "REEL", youtubeVideo: "YOUTUBE", webArticle: "ARTICLE", quote: "QUOTE", image: "IMAGE", quickNote: "NOTE" })[type];
