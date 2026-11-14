export type SearchPlatform = 'douyin' | 'bilibili' | 'wechat';
export type LinkMode = 'save' | 'queue' | 'account';

export const platformNames = {douyin:'抖音', bilibili:'B 站', wechat:'微信视频号'} as const;
const urlPattern = /https?:\/\/[^\s<>"'，。！？；、【】「」“”‘’（）]+/gi;

function cleanLink(raw: string) {
 const text = raw.replaceAll('&amp;', '&').replace(/[.,;!?\]}]+$/, '');
 const extra = (text.match(/\)/g)?.length ?? 0) - (text.match(/\(/g)?.length ?? 0);
 return extra > 0 ? text.replace(new RegExp(`\\){1,${extra}}$`), '') : text;
}

export function publicURL(value: string) {
 const raw = value.match(urlPattern)?.[0];
 if (!raw) throw new Error('请粘贴 http 或 https 视频链接');
 const url = new URL(cleanLink(raw));
 const host = url.hostname.toLowerCase().replace(/\.$/, '');
 if (url.username || url.password || !host.includes('.') || host.endsWith('.local') ||
     host.endsWith('.localhost') || host.includes(':') || /^\d/.test(host)) {
  throw new Error('请使用公开网站的视频链接');
 }
 return url.href;
}

function matchesHost(host: string, domain: string) {
 return host === domain || host.endsWith('.' + domain);
}

export function linkPlatform(url: URL): SearchPlatform | undefined {
 const host = url.hostname;
 if (matchesHost(host, 'douyin.com') || host === 'iesdouyin.com' || host === 'www.iesdouyin.com') return 'douyin';
 if (matchesHost(host, 'bilibili.com') || host === 'b23.tv') return 'bilibili';
 if (matchesHost(host, 'weixin.qq.com') || host === 'finder.video.qq.com') return 'wechat';
}

export function isAccountLink(url: URL) {
 return (url.hostname === 'space.bilibili.com' && /^\/\d+(?:\/|$)/.test(url.pathname)) ||
  (linkPlatform(url) === 'douyin' && /^\/user\/[^/]+/.test(url.pathname));
}

export function referenceKey(url: URL) {
 const platform = linkPlatform(url);
 if (platform === 'bilibili' && matchesHost(url.hostname, 'bilibili.com')) {
  const video = url.pathname.match(/^\/video\/(BV[0-9a-z]+|av\d+)(?:\/|$)/i);
  if (video) return `bilibili:${video[1]}:p${url.searchParams.get('p') ?? '1'}`;
  if (isAccountLink(url)) return `bilibili:account:${url.pathname.split('/')[1]}`;
 }
 if (platform === 'douyin') {
  const video = url.pathname.match(/^\/(?:share\/)?video\/(\d+)(?:\/|$)/);
  if (video) return `douyin:${video[1]}`;
  if (isAccountLink(url)) return `douyin:account:${url.pathname.split('/')[2]}`;
 }
 if (url.hostname === 'b23.tv' || url.hostname === 'v.douyin.com') {
  return url.origin + url.pathname.replace(/\/$/, '');
 }
 return url.href;
}

export function inspectLinks(text: string) {
 const links = new Map<string, {url:string; key:string; title:string; platform?:SearchPlatform; account:boolean}>();
 let invalid = 0;
 let repeated = 0;
 for (const line of text.split(/\r?\n/)) {
  const matches = line.match(urlPattern) ?? [];
  const title = matches.length === 1 ? line.match(/【([^】]+)】|“([^”]+)”|《([^》]+)》/)?.slice(1).find(Boolean) : undefined;
  for (const raw of matches) {
   try {
    const url = new URL(publicURL(raw));
    const key = referenceKey(url);
    if (links.has(key)) { repeated++; continue; }
    const platform = linkPlatform(url);
    const label = platform ? platformNames[platform] : url.hostname;
    const suffix = url.pathname.split('/').filter(Boolean).at(-1)?.slice(0,32);
    links.set(key,{url:url.href,key,platform,account:isAccountLink(url),title:title?.trim().slice(0,100) || (suffix ? `${label} · ${suffix}` : label)});
   } catch { invalid++; }
  }
 }
 return {links:[...links.values()], invalid, repeated};
}

export function searchTarget(platform: SearchPlatform, keyword: string) {
 const query = encodeURIComponent(keyword.trim().slice(0,120));
 if (!query) throw new Error('请填写账号名或作品关键词');
 if (platform === 'douyin') return `https://www.douyin.com/search/${query}`;
 if (platform === 'bilibili') return `https://search.bilibili.com/all?keyword=${query}`;
 if (platform !== 'wechat') throw new Error('请选择搜索平台');
}
