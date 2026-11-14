import React, {useEffect, useState} from 'react';
import type {Bridge, CaptureAction, CaptureTool, InstalledTool, KeyboardStatus, ToolBookmark, TrackpadStatus} from '../types';

const statusText = {ready:'已在后台',starting:'正在启动',stopped:'未启动',missing:'未安装'};
const recordText = {idle:'开始录屏',starting:'取消录制',recording:'停止录屏',busy:'录屏处理中…'};

function errorMessage(error: unknown) {
 return (error instanceof Error ? error.message : String(error))
  .replace(/^Error invoking remote method '[^']+': Error: /,'');
}

const trackpadLabels: Record<TrackpadStatus['state'], string> = {
 ready: '可用', locking: '正在锁定…', locked: '已锁定', unlocking: '正在恢复…', recovery: '需要恢复', unavailable: '不可用',
};

function TrackpadCard({api}: {api: Bridge}) {
 const [status, setStatus] = useState<TrackpadStatus>();
 const [error, setError] = useState('');
 const pending = React.useRef(false);
 const [busy, setBusy] = useState(false);

 useEffect(() => {
  let active = true;
  let refreshId = 0;
  const refresh = async () => {
   if (pending.current) return;
   const id = ++refreshId;
   try {
    const current = await api.trackpadStatus();
    if (active && id === refreshId && !pending.current) {setStatus(current);setError('');}
   } catch (error) {
    if (active && id === refreshId && !pending.current) {setStatus(undefined);setError(errorMessage(error));}
   }
  };
  void refresh();
  const interval = window.setInterval(refresh, 800);
  window.addEventListener('focus', refresh);
  return () => {active = false;window.clearInterval(interval);window.removeEventListener('focus', refresh);};
 }, [api]);

 const state = status?.state;
 const checked = state === 'locked' || state === 'unlocking' || state === 'recovery';
 const available = (state === 'ready' && !!status?.shortcut) || state === 'locked' || state === 'recovery';
 const change = async () => {
  if (pending.current || !available) return;
  pending.current = true;
  setBusy(true);
  setError('');
  try {setStatus(await api.setTrackpadLocked(!checked));}
  catch (error) {setError(errorMessage(error));}
  finally {pending.current = false;setBusy(false);}
 };

 return <article className="tool-card">
  <div className="tool-card-top">
   <span aria-hidden="true" className="tool-icon trackpad"><svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6"><rect x="2.5" y="4.5" width="19" height="15" rx="3"/><path d="M9 16h6" strokeLinecap="round"/></svg></span>
   <span className={'tool-status '+(checked ? 'ready' : '')} role="status">{state ? trackpadLabels[state] : (error ? '不可用' : '正在连接…')}</span>
  </div>
  <div><h2>触控板锁</h2><p>暂停内置触控板，键盘照常使用</p>
   {status?.shortcut && <p className="trackpad-shortcut">快捷键 <kbd>{status.shortcut}</kbd></p>}
   {(error || status?.warning || (state === 'ready' && !status?.shortcut)) && <p role="alert" className="trackpad-warning">{error || status?.warning || '快捷键被占用，暂时无法锁定'}</p>}
  </div>
  <button type="button" role="switch" aria-label="触控板锁" aria-checked={checked} className="trackpad-switch" disabled={!available || busy} onClick={()=>void change()}>
   <span className="switch-track" aria-hidden="true"><span/></span>
   {checked ? '恢复触控板' : '锁定触控板'}
  </button>
 </article>;
}

function KeyboardCards({api}: {api: Bridge}) {
 const [status, setStatus] = useState<KeyboardStatus>();
 const [connection, setConnection] = useState('');
 const [error, setError] = useState<{text:string; card:'keyboard'|'f3'|'f4'}>();
 const [busy, setBusy] = useState(false);
 const generation = React.useRef(0);
 const pending = React.useRef(false);
 useEffect(() => {
  let active = true;
  const refresh = async () => {
   if (pending.current) return;
   const id = ++generation.current;
   try {
    const current = await api.keyboardStatus();
    if (active && id === generation.current) {setStatus(current);setConnection('');}
   } catch (error) {
    if (active && id === generation.current) {setStatus(undefined);setConnection(errorMessage(error));}
   }
  };
  void refresh();
  window.addEventListener('focus', refresh);
  const interval = window.setInterval(refresh, 850);
  return () => {active = false;window.removeEventListener('focus', refresh);window.clearInterval(interval);};
 },[api]);
 const act = async (card:'keyboard'|'f3'|'f4', operation:()=>Promise<KeyboardStatus>) => {
  if (pending.current) return;
  pending.current = true;
  generation.current++;
  setBusy(true);setError(undefined);
  try {setStatus(await operation());}
  catch (error) {setError({card,text:errorMessage(error)});}
  finally {pending.current=false;setBusy(false);}
 };
 const state = status?.state;
 const locked = state === 'locked' || state === 'unlocking' || state === 'recovery';
 const permitted = !!status?.permission;
 const eligible = locked ? state !== 'unlocking' : (state === 'ready' && permitted && !!status?.external);
 const keyWarning = (error?.card === 'keyboard' && error.text) || connection || status?.warning;
 const f3Warning = (error?.card === 'f3' && error.text) || status?.f3Warning;
 const f4Warning = (error?.card === 'f4' && error.text) || status?.f4Warning || (status && !status.f4Supported ? '请更新触控板锁助手以使用 F4' : '');
 const switchIcon = <span className="switch-track" aria-hidden="true"><span/></span>;
 return <>
  <article className="tool-card">
   <div className="tool-card-top">
    <span aria-hidden="true" className="tool-icon trackpad"><svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6"><rect x="2" y="5" width="20" height="14" rx="3"/><path d="M6 9h1m4 0h1m4 0h1M6 13h1m4 0h1m4 0h1M8 16h8" strokeLinecap="round"/></svg></span>
    <span className={'tool-status '+(locked?'ready':'')} role="status">{state === 'ready' && !permitted ? '待授权' : state ? trackpadLabels[state] : (connection ? '不可用' : '正在连接…')}</span>
   </div>
   <div><h2>内置键盘锁</h2><p>只锁 Mac 自带键盘，外接键盘照常用。拔掉外接键盘会自动恢复。</p>
    {state === 'ready' && !status?.external && <p className="trackpad-shortcut">请先连接外接键盘</p>}
    {keyWarning && <p className="trackpad-warning" role="alert">{keyWarning}</p>}
   </div>
   {state === 'ready' && !permitted
    ? <button disabled={busy} onClick={()=>void act('keyboard',()=>api.requestKeyboardPermission())}>允许输入监控…</button>
    : <button type="button" role="switch" aria-label="内置键盘锁" aria-checked={locked} disabled={!eligible || busy} className="trackpad-switch" onClick={()=>void act('keyboard',()=>api.setKeyboardLocked(!locked))}>{switchIcon}{locked?'恢复键盘':'锁定键盘'}</button>}
  </article>
  <article className="tool-card">
   <div className="tool-card-top">
    <span aria-hidden="true" className="tool-icon f3">F3</span>
    <span className={'tool-status '+(status?.f3?'ready':'')} role="status">{status?.f3?'已开启':status?'已关闭':'—'}</span>
   </div>
   <div><h2>F3 录屏快捷键</h2><p>Mac 自带键盘单按 F3 启停轻录。按 Fn + F3 打开调度中心。</p>
    {f3Warning && <p className="trackpad-warning" role="alert">{f3Warning}</p>}
   </div>
   <button type="button" role="switch" aria-label="F3 录屏快捷键" aria-checked={!!status?.f3} disabled={busy || state !== 'ready'} className="trackpad-switch" onClick={()=>void act('f3',()=>api.setF3RecordingShortcut(!status?.f3))}>{switchIcon}{status?.f3?'恢复默认按法':'启用 F3 录屏'}</button>
  </article>
  <article className="tool-card">
   <div className="tool-card-top">
    <span aria-hidden="true" className="tool-icon f3">F4</span>
    <span className={'tool-status '+(status?.f4?'ready':'')} role="status">{status?.f4?'已开启':status?.f4Supported?(status.f4Permission?'已关闭':'待授权'):'—'}</span>
   </div>
   <div><h2>F4 强制退出</h2><p>单按 F4 打开系统的「强制退出应用程序」窗口。按 Fn + F4 打开聚焦。</p>
    {f4Warning&&<p className="trackpad-warning" role="alert">{f4Warning}</p>}
   </div>
   {status?.f4Supported&&!status.f4Permission
    ? <button disabled={busy} onClick={()=>void act('f4',()=>api.requestF4ForceQuitPermission())}>打开辅助功能授权…</button>
    : <button type="button" role="switch" aria-label="F4 强制退出快捷键" aria-checked={!!status?.f4} disabled={busy||state!=='ready'||!status?.f4Supported} className="trackpad-switch" onClick={()=>void act('f4',()=>api.setF4ForceQuitShortcut(!status?.f4))}>{switchIcon}{status?.f4?'恢复默认按法':'启用 F4 强制退出'}</button>}
  </article>
 </>;
}

export function MyTools({api,onMotion}:{api:Bridge;onMotion:()=>void}) {
 const [tool,setTool] = useState<CaptureTool>({status:'starting'});
 const [error,setError] = useState('');
 const [capturePending,setCapturePending] = useState(false);

 useEffect(() => {
  let active = true;
  let refreshing = false;
  const refresh = () => {
   if (refreshing) return;
   refreshing = true;
   api.captureStatus().then(result => { if (active) setTool(result); })
    .catch(error => { if (active) setError(errorMessage(error)); })
    .finally(() => { refreshing = false; });
  };
  refresh();
  window.addEventListener('focus',refresh);
  const interval = window.setInterval(refresh,1500);
  return () => {
   active = false;
   window.removeEventListener('focus',refresh);
   window.clearInterval(interval);
  };
 },[api]);

 const startCapture = async () => {
  setError('');
  setCapturePending(true);
  try { setTool(await api.startCapture()); }
  catch (error) { setError(errorMessage(error)); }
  finally { setCapturePending(false); }
 };

 const capture = async (action: CaptureAction) => {
  setError('');
  setCapturePending(true);
  try {
   await api.controlRecorder(action);
   setTool(await api.captureStatus());
  } catch (error) { setError(errorMessage(error)); }
  finally { setCapturePending(false); }
 };

 return <section className="workbench-content">
  <h1>我的工具</h1>
  {error && <p className="alert error" role="alert">{error}</p>}
  <div className="tool-cards">
   <article className="tool-card">
    <div className="tool-card-top">
     <span aria-hidden="true" className="tool-icon recorder">◉</span>
     <span className={'tool-status '+tool.status}>{statusText[tool.status]}</span>
    </div>
    <div><h2>截录暂存</h2><p>系统截屏自动暂存 · F3 启停录屏 · ⌃⌘4 区域截图</p></div>
    {tool.controls?.unifiedShelf && <div className="capture-actions">
     <button className="primary" disabled={capturePending} onClick={()=>void capture('shelf')}>打开暂存栏</button>
     <button disabled={capturePending || !tool.controls.canScreenshot} onClick={()=>void capture('screenshot')}>区域截图</button>
     <button disabled={capturePending || tool.controls.recording==='busy'} onClick={()=>void capture('record')}>
      {recordText[tool.controls.recording]}
     </button>
     <button disabled={capturePending} onClick={()=>void capture('settings')}>录制设置</button>
    </div>}
    {tool.status==='stopped' && <button disabled={capturePending} onClick={()=>void startCapture()}>启动截录暂存</button>}
    {tool.status==='ready' && !tool.controls?.unifiedShelf && <p>请更新或重开截录暂存。</p>}
   </article>
   <article className="tool-card">
    <div className="tool-card-top"><span aria-hidden="true" className="tool-icon motion">▷</span></div>
    <div><h2>动效拆解</h2><p>打开素材库，选段和拆解</p></div>
    <button className="primary" onClick={onMotion}>进入动效拆解</button>
   </article>
   <TrackpadCard api={api}/>
   <KeyboardCards api={api}/>
  </div>
 </section>;
}

export function ToolFinder({api}:{api:Bridge}) {
 const [installed,setInstalled] = useState<InstalledTool[]>([]);
 const [bookmarks,setBookmarks] = useState<ToolBookmark[]>([]);
 const [query,setQuery] = useState('');
 const [name,setName] = useState('');
 const [url,setUrl] = useState('');
 const [error,setError] = useState('');
 const [saving,setSaving] = useState(false);

 useEffect(() => {
  let active = true;
  void api.installedTools().then(items=>{if(active)setInstalled(items);})
   .catch(error=>{if(active)setError(errorMessage(error));});
  void api.toolBookmarks().then(items=>{if(active)setBookmarks(items);})
   .catch(error=>{if(active)setError(errorMessage(error));});
  return ()=>{active=false;};
 },[api]);

 const act = async (task:()=>Promise<unknown>) => {
  setError('');
  try { await task(); } catch(error) { setError(errorMessage(error)); }
 };
 const save = async () => {
  setSaving(true);
  try {
   await act(async()=>{
    setBookmarks(await api.saveToolBookmark(name,url));
    setName('');
    setUrl('');
   });
  } finally { setSaving(false); }
 };
 const term = query.trim().toLowerCase();
 const filtered = installed.filter(tool=>tool.name.toLowerCase().includes(term));

 return <section className="workbench-content">
  <h1>找工具</h1>
  {error && <p className="alert error" role="alert">{error}</p>}
  <form className="tool-search" onSubmit={event=>{event.preventDefault();if(term)void act(()=>api.searchTools(query));}}>
   <input autoFocus aria-label="搜索本机应用或工具名" placeholder="搜索本机应用或工具名" maxLength={120} value={query} onChange={event=>setQuery(event.target.value)}/>
   <button className="primary" disabled={!term}>网上搜索</button>
  </form>
  <div className="tool-finder-columns">
   <section className="tool-directory">
    <h2>本机应用</h2>
    {filtered.length===0 && <p className="muted">没有匹配的本机应用。</p>}
    <div className="tool-rows">
     {filtered.map(tool=><button className="tool-row" key={tool.path} title={tool.path} onClick={()=>void act(()=>api.openTool(tool.path))}>
      <span>{tool.name}</span><span aria-hidden="true">↗</span>
     </button>)}
    </div>
   </section>
   <section className="tool-directory">
    <h2>网址收藏</h2>
    <form className="tool-bookmark-form" onSubmit={event=>{event.preventDefault();if(url.trim()&&!saving)void save();}}>
     <input aria-label="工具名称（选填）" placeholder="工具名称（选填）" maxLength={100} value={name} onChange={event=>setName(event.target.value)}/>
     <input aria-label="工具网址" placeholder="工具网址" maxLength={2000} value={url} onChange={event=>setUrl(event.target.value)}/>
     <button disabled={saving||!url.trim()}>收藏网址</button>
    </form>
    <div className="tool-rows">
     {bookmarks.map(item=><div className="tool-bookmark" key={item.url}>
      <button className="tool-row" title={item.url} onClick={()=>void act(()=>api.openToolBookmark(item.url))}><span>{item.name}</span><span aria-hidden="true">↗</span></button>
      <button className="tool-remove" aria-label={'移除收藏 '+item.name} onClick={()=>void act(async()=>setBookmarks(await api.removeToolBookmark(item.url)))}>×</button>
     </div>)}
    </div>
   </section>
  </div>
 </section>;
}
