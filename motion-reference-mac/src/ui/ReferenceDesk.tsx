import React, {useEffect, useMemo, useState} from 'react';
import {inspectLinks, platformNames, publicURL, referenceKey, type LinkMode, type SearchPlatform} from '../reference-links';
import type {Bridge, Job, SearchHistoryEntries} from '../types';

const platforms: SearchPlatform[] = ['douyin', 'bilibili', 'wechat'];

type Props = {
 mode: 'links' | 'search';
 setMode: (mode: 'links' | 'search') => void;
 draft: string;
 setDraft: (text: string) => void;
 jobs: Job[];
 api: Bridge;
 onUpdate: (job: Job) => void;
 onOpen: (job: Job) => void;
 onClose: () => void;
};

export function ReferenceDesk({mode,setMode,draft,setDraft,jobs,api,onUpdate,onOpen,onClose}: Props) {
 const [platform,setPlatform] = useState<SearchPlatform>('douyin');
 const [keyword,setKeyword] = useState('');
 const [history,setHistory] = useState<SearchHistoryEntries>({douyin:[],bilibili:[],wechat:[]});
 useEffect(() => {
  let active = true;
  api.searchHistory().then(entries => {
   if (active) setHistory(entries);
  }).catch(() => {});
  return () => { active = false; };
 }, [api]);
 const [busy,setBusy] = useState(false);
 const [feedback,setFeedback] = useState('');
 const [failed,setFailed] = useState(false);
 const {links,invalid,repeated} = useMemo(() => inspectLinks(draft), [draft]);
 const known = useMemo(() => {
  const map = new Map<string,Job>();
  for (const job of jobs) {
   if (!job.sourceUrl) continue;
   try {
    const key = referenceKey(new URL(publicURL(job.sourceUrl)));
    if (!map.has(key) || (job.sourceFile && !map.get(key)?.sourceFile)) map.set(key,job);
   } catch { /* Ignore malformed entries from older versions. */ }
  }
  return map;
 }, [jobs]);
 const accounts = jobs.filter(job => job.referenceKind === 'account');
 const work = async (action: () => Promise<void>) => {
  if (busy) return;
  setBusy(true);
  setFeedback('');
  setFailed(false);
  try { await action(); }
  catch (error) {
   setFailed(true);
   setFeedback((error as Error).message.replace(/^Error invoking remote method '[^']+': Error: /,''));
  } finally { setBusy(false); }
 };
 const search = (site = platform, term = keyword) => void work(async () => {
  setKeyword(term.trim());
  setHistory(await api.searchReferences(site,term));
  if (site === 'wechat') setFeedback('关键词已复制。在微信打开「发现 → 视频号」，点搜索后粘贴。');
 });
 const submit = (action: LinkMode) => void work(async () => {
  const result = await api.submitLinks(draft,action);
  result.jobs.forEach(onUpdate);
  setFeedback(`新增 ${result.added} 条 · 已在库 ${result.existing} 条 · 加入下载队列 ${result.queued} 条`);
  if (action === 'account') setMode('search');
 });
 const saveAccount = () => void work(async () => {
  onUpdate(await api.saveAccount(keyword,platform));
  setFeedback('账号已收藏，可以从下方再次打开或搜索。');
 });
 const paste = () => void work(async () => {
  const text = await api.readLinkClipboard();
  if (!text.trim()) { setFeedback('剪贴板里没有文字，请先复制视频链接或分享文字。'); return; }
  setDraft(text);
 });
 const allowed = !!links.length && links.length <= 20 && !busy;
 const downloadable = links.some(link => !link.account && link.platform !== 'wechat' &&
  (!known.has(link.key) || (known.get(link.key)?.progress.state === 'idle' && !known.get(link.key)?.sourceFile &&
  known.get(link.key)?.referenceKind !== 'account')));

 return <section className="reference-desk" aria-label="找参考与链接导入">
  <header className="reference-header">
   <h1>{mode === 'search' ? '找参考' : '收链接'}</h1>
   <div className="reference-heading-actions">
    <button onClick={()=>setMode(mode==='search'?'links':'search')}>{mode==='search'?'收链接':'找参考'}</button>
    <button onClick={onClose}>参考库</button>
   </div>
  </header>
  {feedback && <p role="status" className={failed ? 'alert error' : 'alert'}>{feedback}</p>}
  {mode === 'search' ? <>
   <div className="reference-card reference-search-card">
    <div className="reference-platforms" aria-label="搜索平台">
     {platforms.map(site => <button key={site} aria-pressed={platform === site} onClick={() => setPlatform(site)}>{platformNames[site]}</button>)}
    </div>
    <form className="reference-search" onSubmit={e => {e.preventDefault();if (keyword.trim()) search();}}>
     <input autoFocus aria-label="搜索账号或关键词" placeholder="搜索账号或关键词" value={keyword} maxLength={120} onChange={e=>setKeyword(e.target.value)}/>
     <button className="primary" disabled={busy || !keyword.trim()}>{platform === 'wechat' ? '复制并打开微信' : '搜索'}</button>
    </form>
    <h2>搜索记录</h2>
    {history[platform].length > 0 ? <div className="reference-history" aria-label={platformNames[platform] + '搜索记录'}>
     {history[platform].map(term => <button key={term} disabled={busy} onClick={() => search(platform, term)}>{term}</button>)}
    </div> : <p className="reference-history-empty">搜索后会在这里显示。</p>}
   </div>
   <details className="reference-accounts">
    <summary>账号收藏{accounts.length > 0 && ` · ${accounts.length}`}</summary>
    <button type="button" disabled={busy || !keyword.trim()} onClick={saveAccount}>收藏当前账号名</button>
    {accounts.map(account => <div className="reference-row" key={account.id}>
     <div><strong>{account.title}</strong><small>{account.searchPlatform ? platformNames[account.searchPlatform] : '账号主页'}</small></div>
     <button disabled={busy} onClick={() => account.sourceUrl
      ? void work(() => api.openSource(account.id))
      : search(account.searchPlatform ?? 'wechat',account.title)}>{account.sourceUrl ? '打开主页' : '搜索账号'}</button>
    </div>)}
   </details>
  </> : <div className="reference-card">
   <div className="reference-field-heading">
    <label htmlFor="reference-links">视频链接或分享文字</label>
    <button disabled={busy} onClick={paste}>粘贴剪贴板</button>
   </div>
   <textarea id="reference-links" value={draft} rows={6} maxLength={20_000} placeholder="每行一条链接，也可以整段粘贴平台分享文字。" onChange={e=>setDraft(e.target.value)}/>
   <p className="muted">识别 {links.length} 条 · 重复 {repeated} 条{invalid ? ` · 无效 ${invalid} 条` : ''}{links.length > 20 ? ' · 每批最多 20 条' : ''}</p>
   <div className="reference-list">
    {links.slice(0,20).map(link => {
     const job = known.get(link.key);
     return <div className="reference-row" key={link.key}>
      <div><strong>{link.title}</strong><small title={link.url}>{link.url}</small></div>
      {job && job.referenceKind !== 'account'
       ? <button onClick={()=>onOpen(job)}>查看库内条目</button>
       : <span>{job ? '已收藏' : link.account ? '账号主页' : link.platform === 'wechat' ? '可先收藏' : '待保存'}</span>}
     </div>;
    })}
   </div>
   <div className="reference-actions">
    <button className="primary" disabled={!allowed} onClick={()=>submit('save')}>保存到参考库</button>
    <button disabled={!allowed || !downloadable} onClick={()=>submit('queue')}>加入下载队列</button>
    <button disabled={!allowed} onClick={()=>submit('account')}>收藏为账号主页</button>
   </div>
   <p className="muted">已收藏的作品可以稍后取视频或关联本地文件。下载成功后会进入原来的初步分类流程。</p>
  </div>}
 </section>;
}
