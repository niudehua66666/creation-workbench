import React,{useState,useEffect,useRef} from 'react';
import {createRoot} from 'react-dom/client';
import {categories,taxonomy,type Job,type Bridge,type Environment,type Category,type EagleClipResult,type MotionClipDraft} from '../types';
import './style.css';
import {adjustRange} from '../range';
import {actionClipDraft} from '../action-clips';
import {detectedCategories,jobCategories,segmentCategories} from '../motion-categories';
import {EagleActionClips} from './EagleActionClips';
import {RangeTimeline} from './RangeTimeline';
import {ReferenceDesk} from './ReferenceDesk';
import {MyTools, ToolFinder} from './Workbench';
import {linkPlatform, publicURL} from '../reference-links';
declare global{interface Window{motion:Bridge}}
const api=window.motion;
const stages=['读取视频','分类标注','找候选','拆解','生成','渲染','对照'];
const time=(n:number)=>`${Math.floor(n/60).toString().padStart(2,'0')}:${(n%60).toFixed(2).padStart(5,'0')}`;
const metric=(v:number|null)=>v===null?'未获取':v>=10000?(v/10000).toFixed(1)+'万':v.toLocaleString();
function canFetchReference(url:string) {
 try {return linkPlatform(new URL(publicURL(url)))!=='wechat';}catch{return false;}
}
type WorkbenchPage = 'home' | 'motion' | 'search' | 'links' | 'tools';
function App(){
 const[jobs,setJobs]=useState<Job[]>([]),[selected,setSelected]=useState(''),[env,setEnv]=useState<Environment>(),[error,setError]=useState(''),[notice,setNotice]=useState(''),[draft,setDraft]=useState(''),[page,setPage]=useState<WorkbenchPage>('home'),[query,setQuery]=useState(''),[scope,setScope]=useState('全部口径'),[sort,setSort]=useState('recent'),[category,setCategory]=useState('全部类别'),[authorFilter,setAuthorFilter]=useState('全部作者'),[traffic,setTraffic]=useState('全部流量'),[minLikes,setMinLikes]=useState(''),[tab,setTab]=useState('选段与动作'),[busyUI,setBusyUI]=useState(false),[drag,setDrag]=useState(false),[advanced,setAdvanced]=useState(false),[authors,setAuthors]=useState<string[]>([]),[newAuthor,setNewAuthor]=useState(''),[addingAuthor,setAddingAuthor]=useState(false);
 const desk = page==='search' || page==='links' ? page : null;
 const setDesk = (mode:'links'|'search'|null) => setPage(mode ?? 'motion');
 const videos=jobs.filter(j=>j.referenceKind!=='account');const job=videos.find(j=>j.id===selected);const running=!!job&&['running','queued'].includes(job.progress.state)||busyUI;const pending=jobs.filter(j=>['running','queued'].includes(j.progress.state)).sort((a,b)=>(a.progress.state==='running'?-1:1)-(b.progress.state==='running'?-1:1)||(a.progress.queuedAt??0)-(b.progress.queuedAt??0));
 const update=(j:Job)=>setJobs(old=>{const current=old.find(x=>x.id===j.id);return current&&current.progress.updatedAt>j.progress.updatedAt?old:[j,...old.filter(x=>x.id!==j.id)].sort((a,b)=>b.createdAt-a.createdAt);});
 useEffect(()=>{api.list().then(j=>{setJobs(j);const first=j.find(item=>item.referenceKind!=='account');setSelected(first?.id??'');if(first&&!first.classification?.confirmedAt)setTab('分类与作者');});api.environment().then(setEnv).catch(e=>setError(String(e)));return api.subscribe(update);},[]);
 useEffect(()=>{api.authors().then(setAuthors).catch(()=>{});},[jobs.map(j=>j.author).join('|')]);
 const attempt=async<T,>(fn:()=>Promise<T>):Promise<T|undefined>=>{setError('');try{return await fn();}catch(e){setError((e as Error).message.replace(/^Error invoking remote method '[^']+': Error: /,''));}};
 const act=async(a:string,data?:unknown)=>{if(!job)return;const j=await attempt(()=>api.action(job.id,a,data));if(j)update(j);};
 const imported=async(fn:()=>Promise<Job|Job[]|null>)=>{setBusyUI(true);try{const result=await attempt(fn);for(const j of result?(Array.isArray(result)?result:[result]):[]){update(j);openJob(j);}}finally{setBusyUI(false);}};
 const openJob=(j:Job)=>{setDesk(null);setSelected(j.id);setTab(j.classification?.confirmedAt?'选段与动作':'分类与作者');};
 useEffect(()=>{
  const onKey=(event:KeyboardEvent)=>{
   if(event.metaKey&&event.shiftKey&&event.code==='KeyV'){
    event.preventDefault();setDesk('links');
    void api.readLinkClipboard().then(text=>{if(text.trim())setDraft(text);}).catch(()=>setError('无法读取剪贴板，请按 ⌘V 粘贴链接'));
   }
  };
  window.addEventListener('keydown',onKey);
  return ()=>window.removeEventListener('keydown',onKey);
 },[]);
 const search=query.toLowerCase();
 const filtered=videos.filter(j=>{
  const types=jobCategories(j);
  return `${j.title} ${j.author} ${types.join(' ')}`.toLowerCase().includes(search)
   &&(category==='全部类别'||types.some(type=>type===category)||category==='待分类'&&!types.length)
   &&(authorFilter==='全部作者'||j.author===authorFilter||authorFilter==='作者待补充'&&!j.author)
   &&(scope==='全部口径'||j.metrics.scope===scope)&&(traffic==='全部流量'||j.metrics.traffic===traffic)
   &&(!minLikes||(j.metrics.likes!==null&&j.metrics.likes>=Number(minLikes)));
 }).sort((a,b)=>sort==='recent'?b.createdAt-a.createdAt:((b.metrics[sort as 'views'|'likes']??-1)-(a.metrics[sort as 'views'|'likes']??-1)));
 return <div className={'app'+(page==='motion'?'':' workbench-wide')} onDragOver={e=>{e.preventDefault();if(e.dataTransfer.types.includes('Files'))setDrag(true);}} onDragLeave={e=>{if(!e.relatedTarget)setDrag(false);}} onDrop={e=>{e.preventDefault();setDrag(false);const files=Array.from(e.dataTransfer.files);if(files.length&&!busyUI)void imported(async()=>{const result:Job[]=[];for(const f of files){const j=await attempt(()=>api.importVideo(api.filePath(f),files.length===1&&page==='motion'&&job&&!job.sourceFile&&!running?job.id:undefined));if(j){result.push(j);update(j);}}return result;});}}>
  <header className="titlebar workbench-titlebar">
   <span className="app-name">创作工作台</span>
   <nav className="workbench-nav" aria-label="工作台导航">
    <button aria-pressed={page==='home'||page==='motion'} onClick={()=>setPage('home')}>我的工具</button>
    <button aria-pressed={!!desk} onClick={()=>setPage('search')}>找参考</button>
    <button aria-pressed={page==='tools'} onClick={()=>setPage('tools')}>找工具</button>
   </nav>
  </header>
  {page==='motion'&&<aside>
   <h2 className="workbench-library-title">动效拆解</h2>
   <button className="primary wide" disabled={busyUI} onClick={()=>void imported(()=>api.pickVideo())}>＋ 导入视频</button>
   <button className="workbench-link-entry" title="⌘⇧V 从剪贴板收链接" onClick={()=>setDesk('links')}>收链接</button>
   <div className="section-label">参考库 <span>{videos.length}</span></div><input className="search" aria-label="搜索参考" placeholder="搜索标题、博主、类别" value={query} onChange={e=>setQuery(e.target.value)}/>
   <div className="filters"><select aria-label="九类素材筛选" value={category} onChange={e=>setCategory(e.target.value)}><option>全部类别</option>{taxonomy.map(g=><optgroup key={g.group} label={g.group}>{g.items.map(i=><option key={i.name}>{i.name}</option>)}</optgroup>)}<option>待分类</option></select><select aria-label="作者筛选" value={authorFilter} onChange={e=>setAuthorFilter(e.target.value)}><option>全部作者</option><option>作者待补充</option>{authors.map(a=><option key={a}>{a}</option>)}</select></div><button className="add-author-toggle" onClick={()=>setAddingAuthor(!addingAuthor)}>＋ 新增作者</button>{addingAuthor&&<div className="author-add"><input aria-label="新增作者名称" placeholder="例如：影视飓风" value={newAuthor} onChange={e=>setNewAuthor(e.target.value)}/><button disabled={!newAuthor.trim()} onClick={()=>void attempt(async()=>{setAuthors(await api.addAuthor(newAuthor));setNotice('已添加作者“'+newAuthor.trim()+'”，导入后可在作者栏选择。');setNewAuthor('');setAddingAuthor(false);})}>添加</button></div>}<details className="heat-filters"><summary>热度筛选（可选）</summary><div className="filters"><select aria-label="数据口径" value={scope} onChange={e=>{setScope(e.target.value);setSort('recent');}}>{['全部口径','单条视频实测','账号汇总','预期播放量','未知'].map(x=><option key={x}>{x}</option>)}</select><select aria-label="排序" value={sort} onChange={e=>setSort(e.target.value)}><option value="recent">最近导入</option><option value="views" disabled={scope==='全部口径'||traffic==='全部流量'}>播放量 ↓</option><option value="likes" disabled={scope==='全部口径'||traffic==='全部流量'}>点赞量 ↓</option></select></div>
   <div className="filters"><select aria-label="流量口径筛选" value={traffic} onChange={e=>{setTraffic(e.target.value);setSort('recent');}}>{['全部流量','全部','非营销','未知'].map(v=><option key={v}>{v}</option>)}</select><input aria-label="最低点赞量" type="number" min="0" placeholder="最低点赞数" value={minLikes} onChange={e=>setMinLikes(e.target.value)}/></div></details><div className="job-list">{filtered.map(j=><button key={j.id} className={'job-row '+(j.id===selected?'selected':'')} onClick={()=>openJob(j)}><div className="job-symbol">{j.outputVersion?'▧':'▷'}</div><div><strong>{j.title}</strong><small>{jobCategories(j).join(' · ')||'待分类'} · {j.author||'作者待补充'}</small><small>{j.media?time(j.media.duration):'等待视频'} · {j.classification?.confirmedAt?'已标注':'待核对标注'}</small><span className={'status '+j.progress.state}>{j.progress.state==='queued'?`排队第 ${j.progress.queuePosition??1} 位`:j.progress.state==='running'?j.progress.stage:j.outputVersion?'可编辑预览':j.progress.state==='failed'?'需要处理':j.progress.state==='cancelled'?'已取消':j.progress.state==='interrupted'?'可继续处理':j.progress.state==='idle'&&j.sourceUrl?'已收藏链接':'参考片段'}</span></div></button>)}{!filtered.length&&<p className="muted small">还没有匹配的参考</p>}</div>
   <div className="env"><span className={env?.signedIn?'green':'muted'}>●</span> {env?env.signedIn?'Codex 已连接':'Codex 需要登录':'正在连接 Codex…'}<button onClick={()=>void attempt(async()=>setEnv(await api.environment()))} title="检查连接">↻</button><small>视频留在本机，分析会发送参考帧至 Codex。</small></div>
  </aside>}
  <main>{pending.length>0&&<section className="queue-banner" aria-label="后台任务队列"><div><strong>后台任务 · {pending.length} 项</strong><small>按顺序处理 · 可导入、浏览和整理其他素材</small></div><div className="queue-items">{pending.map(j=><div key={j.id}><button className="queue-title" onClick={()=>openJob(j)}><span className={j.progress.state==='running'?'green':''}>{j.progress.state==='running'?'处理中':`等候 ${j.progress.queuePosition??1}`}</span> {j.title}</button><button aria-label={'取消任务 '+j.title} onClick={()=>void attempt(async()=>update(await api.action(j.id,'cancel')))}>×</button></div>)}</div></section>}{error&&<div className="alert error" role="alert">{error}<button onClick={()=>setError('')}>×</button></div>}{notice&&<div className="alert">{notice}<button onClick={()=>setNotice('')}>×</button></div>}
   {page==='home'?<MyTools api={api} onMotion={()=>setPage('motion')}/>:page==='tools'?<ToolFinder api={api}/>:desk?<ReferenceDesk mode={desk} setMode={setDesk} draft={draft} setDraft={setDraft} jobs={jobs} api={api} onUpdate={update} onOpen={openJob} onClose={()=>setDesk(null)}/>:job?<><div className="project-heading"><div><div className="eyebrow">REFERENCE / {new Date(job.createdAt).toLocaleDateString('zh-CN')}</div><h1>{job.analysis?.title??job.title}</h1><p>{job.media?`${job.media.width} × ${job.media.height} · ${job.media.fps.toFixed(2)} fps`:'支持本地视频和可下载链接'}{job.author&&` · ${job.author}`}</p></div><div className="heading-actions"><button onClick={()=>void attempt(()=>api.reveal(job.id))}>打开文件夹</button>{job.sourceUrl&&<button onClick={()=>void attempt(()=>api.openSource(job.id))}>原视频 ↗</button>}</div></div>
   {!job.sourceFile&&job.sourceUrl&&<div className="reference-source-actions">
    <span>来源已保留，取得视频后即可开始分类。</span>
    {canFetchReference(job.sourceUrl)&&<button className="primary" disabled={running} onClick={()=>void act('fetch')}>获取视频</button>}
    <button disabled={running} onClick={()=>void attempt(async()=>{const attached=await api.attachVideo(job.id);if(attached)update(attached);})}>关联本地视频</button>
   </div>}
   <Progress job={job} advanced={advanced} onCancel={()=>void act('cancel')} onRetry={()=>void act('retry')}/>
   <nav>{(advanced?['分类与作者','选段与动作','详细拆解','工程编辑','来源数据']:['分类与作者','选段与动作','来源数据']).map(t=><button key={t} className={tab===t?'active':''} onClick={()=>setTab(t)}>{t}</button>)}<button className="advanced-toggle" onClick={()=>{setAdvanced(!advanced);setTab('选段与动作');}}>{advanced?'收起高级复刻':'高级复刻（可选）'}</button></nav>
   {tab==='分类与作者'&&<ClassificationView key={job.id} job={job} authors={authors} disabled={running} onCandidates={()=>void act('candidates')} save={v=>attempt(async()=>{update(await api.action(job.id,'classification',v));setTab('选段与动作');})}/>}
   {tab==='选段与动作'&&!job.classification?.confirmedAt&&<div className="alert">先在“分类与作者”中保存标注，再选择片段拆解。<button onClick={()=>setTab('分类与作者')}>→</button></div>}
   {tab==='选段与动作'&&<Compare key={job.id} job={job} advanced={advanced} onBrief={r=>void act('brief',r)} onSaveClips={async (createdAt,library,clips)=>{
    const result=await api.saveActionClips(job.id,createdAt,library,clips);
    setNotice(`已保存 ${result.saved} 条动作到 Eagle「动效拆解」。`);
    return result;
   }} onWaveform={()=>void act('waveform')} onCopy={()=>void attempt(async()=>{await api.copyBrief(job.id);setNotice('动作说明已复制，可以粘贴给 GPT。');})} onExport={r=>void attempt(async()=>{setBusyUI(true);try{update(await api.action(job.id,'selection',r));const p=await api.export(job.id,'editing');if(p)setNotice('已导出剪辑素材：'+p);}finally{setBusyUI(false);}})} disabled={running||!job.classification?.confirmedAt} onSelect={r=>void act('selection',r)} onGenerate={r=>void act('generate',r)} onCandidates={()=>void act('candidates')} onMarkers={m=>void act('markers',m)}/>}
   {tab==='详细拆解'&&<AnalysisView job={job} onGenerate={()=>void act('generate')} disabled={running||!job.classification?.confirmedAt}/>}
   {tab==='工程编辑'&&<Editor key={job.id} job={job} disabled={running} save={async p=>update(await api.action(job.id,'props',p))} render={async()=>update(await api.action(job.id,'render'))} image={key=>attempt(async()=>{const j=await api.image(job.id,key);if(j)update(j);})} onExport={kind=>void attempt(async()=>{const p=await api.export(job.id,kind);if(p)setNotice('已导出到：'+p);})} onEagle={()=>void attempt(async()=>{setBusyUI(true);try{const j=await api.action(job.id,'eagle');update(j);setNotice('已保存到 Eagle「动效拆解」，并读回核验。');}finally{setBusyUI(false);}})}/>}
   {tab==='来源数据'&&<Metadata key={job.id} job={job} disabled={running} save={v=>void act('metadata',v)}/>}
   </>:<div className="empty"><div className="eyebrow">YOUR MOTION NOTEBOOK</div><h1>把喜欢的那几秒<br/><em>收进你的动作素材库。</em></h1><p>拖入视频，先按九类整理，标记作者和借鉴点。<br/>再选片段，得到简短动作说明，带到剪映或达芬奇。</p><div className="empty-drop"><span>↧</span><strong>将视频拖到这里</strong><small>MP4 · MOV · WebM</small><button className="primary" disabled={busyUI} onClick={()=>void imported(()=>api.pickVideo())}>选择参考视频</button></div><div className="flow"><span>01 分类与作者</span><i>→</i><span>02 选段拆解</span><i>→</i><span>03 看懂动作</span><i>→</i><span>04 导出剪辑素材</span></div></div>}
  </main>{drag&&<div className="drag-cover">放入视频，开始拆解</div>}
 </div>;
}
function ClassificationView({job,authors,disabled,onCandidates,save}:{job:Job;authors:string[];disabled:boolean;onCandidates:()=>void;save:(v:unknown)=>Promise<unknown>}){
 const[primary,setPrimary]=useState<Category|'待分类'>(job.classification?.primary??'待分类'),[secondary,setSecondary]=useState<Category[]>(job.classification?.secondary??[]),[author,setAuthor]=useState(job.author),[sourceUrl,setSourceUrl]=useState(job.sourceUrl),[note,setNote]=useState(job.classification?.note??'');
 useEffect(()=>{setPrimary(job.classification?.primary??'待分类');setSecondary(job.classification?.secondary??[]);setAuthor(job.author);setSourceUrl(job.sourceUrl);setNote(job.classification?.note??'');},[JSON.stringify(job.classification),job.author,job.sourceUrl]);
 const additional=detectedCategories(job).filter(type=>type!==primary&&!secondary.includes(type));
 return <div className="classification"><div className="intake-heading"><div><span className="eyebrow">FIRST / 先整理素材</span><h2>这条素材包含哪些类型，来自谁？</h2><p>沿用你的四大类、九小类。先保存分类、作者与借鉴点，再选段拆解。</p></div><span className="classification-badge">{job.classification?.confirmedAt?'已标注':'初步分类 · 待核对'}</span></div>
 <div className="intake-context">{job.sourceFile&&<video className="intake-video" controls muted preload="metadata" src={api.media(job.id,'source-preview.mp4')}/>}
 <div className="classification-reason"><b>{disabled?'正在读取与分类…':job.classification?.confirmedAt?'已归档类别':'初步判断'}：{[primary,...secondary].join(' · ')}</b><p>{job.classification?.reason||'可以先查看视频，再选择主类别和同时出现的其他类型。'}</p>{job.media&&<button disabled={disabled} onClick={onCandidates}>重新识别类型 · 使用 Codex</button>}</div></div>
 <div className="taxonomy-grid">{taxonomy.map(g=><section key={g.group}><h3>{g.group}</h3><div>{g.items.map(i=><button key={i.name} className={primary===i.name?'chosen':''} disabled={disabled} onClick={()=>{setPrimary(i.name);setSecondary(types=>types.includes(i.name)&&primary!=='待分类'?[...types.filter(v=>v!==i.name),primary]:types.filter(v=>v!==i.name));}}><strong>{i.name==='文献'?'文献参考':i.name==='PNG'?'PNG / 抠图':i.name}</strong><span>{i.description}</span></button>)}</div></section>)}</div>
 <div className="secondary-tags"><span>其他类型 <small>可多选</small></span>{categories.filter(c=>c!==primary).map(c=><button key={c} disabled={disabled} className={secondary.includes(c)?'chosen':''} aria-pressed={secondary.includes(c)} onClick={()=>setSecondary(secondary.includes(c)?secondary.filter(v=>v!==c):[...secondary,c])}>{secondary.includes(c)?'✓ ':''}{c}</button>)}</div>
 {job.classification?.confirmedAt&&!!additional.length&&<p className="muted small">识别到 {additional.join(' · ')}，可在上方加到归档分类。</p>}
 <div className="fields"><label>作者 / 博主（可直接填写新作者）<input list="known-authors" disabled={disabled} aria-label="素材作者" placeholder="选择已有作者，或输入任意新作者" value={author} onChange={e=>setAuthor(e.target.value)}/><datalist id="known-authors">{authors.map(a=><option key={a} value={a}/>)}</datalist><small>{job.classification?.authorSource??'未获取'}{job.classification?.authorEvidence?' · '+job.classification.authorEvidence:''}</small></label><label>来源链接<input disabled={disabled} aria-label="素材来源链接" placeholder="可选，保留原视频地址" value={sourceUrl} onChange={e=>setSourceUrl(e.target.value)}/></label></div>
 <label className="annotation-field">标注 / 借鉴点<textarea disabled={disabled} aria-label="素材标注" rows={3} placeholder="例如：文献页面倾斜进入，关键结论逐行高亮" value={note} onChange={e=>setNote(e.target.value)}/></label>
 <div className="intake-save"><button className="primary" disabled={disabled||primary==='待分类'} onClick={()=>void save({primary,secondary,author,sourceUrl,note})}>保存标注，开始选段 →</button><small>{author?'作者与类别会一起进入素材库，可随时修改。':'作者未知也可先归档，将显示“作者待补充”。'}</small></div></div>;
}
function Progress({job,advanced,onCancel,onRetry}:{job:Job;advanced:boolean;onCancel:()=>void;onRetry:()=>void}){const[now,setNow]=useState(Date.now());useEffect(()=>{const id=setInterval(()=>setNow(Date.now()),1000);return()=>clearInterval(id);},[]);const p=job.progress,running=p.state==='running',queued=p.state==='queued';const elapsed=Math.max(0,(running?now:p.finishedAt??p.updatedAt)-p.startedAt)/1000;const ratio=p.total?Math.min(1,(p.done??0)/p.total):null;const stageElapsed=(now-p.stageAt)/1000;const estimate=p.estimate&&stageElapsed<p.estimate[1]?`同阶段历史估计还需 ${Math.max(0,Math.round(p.estimate[0]-stageElapsed))}～${Math.ceil(p.estimate[1]-stageElapsed)} 秒`:'完成时间暂无法估计';return <section className="progress-card"><div className="steps">{advanced?stages.map((s,i)=><span key={s} className={i<stages.indexOf(p.stage)?'done':s===p.stage?'current':''}><b>{i<stages.indexOf(p.stage)?'✓':i+1}</b>{s}</span>):<span>快速流程 · 分类作者 → 选段 → 动作说明 / 导出</span>}</div><div className="progress-detail"><span className={running?'pulse':''}>●</span><strong>{job.classification?.confirmedAt&&p.state==='ready'&&!job.outputVersion&&p.stage==='找候选'?'类别、作者与标注已保存，可以选择片段拆解':p.detail}</strong><small>{queued?'尚未开始':`已用 ${Math.floor(elapsed/60)}分${Math.floor(elapsed%60)}秒`}</small>{running||queued?<button onClick={onCancel}>取消</button>:['failed','interrupted','cancelled'].includes(p.state)?<button onClick={onRetry}>继续处理</button>:null}</div>{running&&<><div className={'meter '+(ratio===null?'indeterminate':'')}><i style={{width:ratio===null?'30%':`${ratio*100}%`}}/></div><div className="progress-foot">{ratio!==null?`已处理 ${(p.done??0).toFixed(1)} / ${p.total?.toFixed(1)} · ${Math.round(ratio*100)}%`:estimate}<span>以实际处理事件更新</span></div></>}</section>;}
type SaveClips=(createdAt:number,library:string,clips:MotionClipDraft[])=>Promise<EagleClipResult>;
function Compare({job,advanced,disabled,onSelect,onGenerate,onCandidates,onMarkers,onBrief,onExport,onCopy,onWaveform,onSaveClips}:{job:Job;advanced:boolean;onBrief:(r:{start:number;end:number})=>void;onExport:(r:{start:number;end:number})=>void;onCopy:()=>void;onWaveform:()=>void;onSaveClips:SaveClips;disabled:boolean;onSelect:(v:{start:number;end:number})=>void;onGenerate:(v:{start:number;end:number})=>void;onCandidates:()=>void;onMarkers:(n:number[])=>void}){
 const [reviewAction,setReviewAction]=useState<{index:number;createdAt:number}>();
 const viewer=useRef<HTMLDivElement>(null);
 const brief=job.brief;
 const reviewIndex=brief&&reviewAction?.createdAt===brief.createdAt?reviewAction.index:undefined;
 const review=brief&&reviewIndex!==undefined?actionClipDraft(brief,reviewIndex):undefined;
 const[source,setSource]=useState(false),[start,setStart]=useState(job.selection?.start??0),[end,setEnd]=useState(job.selection?.end??Math.min(8,job.media?.duration??8)),[playing,setPlaying]=useState(false),[clock,setClock]=useState(0),[rate,setRate]=useState(1),[sound,setSound]=useState(false),[loop,setLoop]=useState(false);const a=useRef<HTMLVideoElement>(null),b=useRef<HTMLVideoElement>(null),pendingSeek=useRef<{time:number;play?:boolean}|null>(null);const comparison=advanced&&!!job.outputVersion&&!source;const range=job.referenceRange??job.selection;const duration=comparison?(range?range.end-range.start:4):job.media?.duration??0;const replicaDuration=job.renderedProps?Number(JSON.parse(job.renderedProps).durationSeconds):duration;const ratio=comparison?replicaDuration/duration:1;
 useEffect(()=>{setStart(job.selection?.start??0);setEnd(job.selection?.end??Math.min(8,job.media?.duration??8));},[job.selection?.start,job.selection?.end]);
 useEffect(()=>{if(!pendingSeek.current){a.current?.pause();b.current?.pause();setPlaying(false);setClock(0);}},[comparison,job.outputVersion]);
 const reviewEnd=review?.end;
 useEffect(()=>{
  let frame=0;
  const tick=()=>{
   const original=a.current,replica=b.current;
   if(original){
    const position=original.currentTime;
    setClock(position);
    if(replica&&playing&&Math.abs(position*ratio-replica.currentTime)>.07)replica.currentTime=Math.min(replica.duration||Infinity,position*ratio);
    if(playing&&!original.seeking&&reviewEnd!==undefined&&position>=reviewEnd){
     original.pause();
     setPlaying(false);
    }else if(!comparison&&reviewEnd===undefined&&loop&&playing&&(position>=end-.01||position<start-.05)){
     original.currentTime=start;
     if(original.paused)void original.play().catch(()=>setPlaying(false));
    }else if(original.ended){setPlaying(false);replica?.pause();}
   }
   frame=requestAnimationFrame(tick);
  };
  frame=requestAnimationFrame(tick);
  return()=>cancelAnimationFrame(frame);
 },[playing,ratio,comparison,loop,start,end,reviewEnd]);
 const seek=(t:number)=>{
  const value=Math.max(0,Math.min(Math.max(0,duration-.001),t));
  if(a.current)a.current.currentTime=value;
  if(b.current)b.current.currentTime=value*ratio;
  setClock(value);
 };
 const startPlayback=()=>{
  if(!a.current)return;
  setPlaying(true);
  for(const [video,mult] of [[a.current,1],[b.current,ratio]] as const){
   if(!video)continue;
   video.playbackRate=Math.max(.0625,Math.min(16,rate*mult));
   void video.play().catch(()=>{if(a.current===video||b.current===video)setPlaying(false);});
  }
 };
 const pause=()=>{a.current?.pause();b.current?.pause();setPlaying(false);};
 const loaded=()=>{
  const request=pendingSeek.current;
  pendingSeek.current=null;
  if(!request)return;
  seek(request.time);
  if(request.play)startPlayback();
 };
 const previewAction=(index:number,scroll=false)=>{
  if(!brief?.actions[index]||!job.sourceFile)return;
  const clip=actionClipDraft(brief,index);
  setReviewAction({index,createdAt:brief.createdAt});
  if(comparison||!a.current||a.current.readyState===0){
   pause();
   pendingSeek.current={time:clip.start,play:true};
   setSource(true);
  }else{
   seek(clip.start);
   startPlayback();
  }
  if(scroll)viewer.current?.scrollIntoView({block:'start',behavior:'instant'});
 };
 const exitReview=()=>{
  if(reviewIndex===undefined)return;
  pendingSeek.current=null;
  pause();
  setReviewAction(undefined);
 };
 const scrub=(time:number)=>{
  if(review&&(time<review.start||time>=review.end))exitReview();
  seek(time);
 };
 const play=()=>{
  if(pendingSeek.current?.play){pendingSeek.current.play=false;pause();return;}
  if(playing){pause();return;}
  if(review){
   const position=a.current?.currentTime??clock;
   if(position<review.start||position>=review.end||a.current?.ended)seek(review.start);
  }else if(!comparison&&loop)seek(start);
  else if(a.current?.ended)seek(0);
  startPlayback();
 };
 const setSpeed=(r:number)=>{setRate(r);if(a.current)a.current.playbackRate=r;if(b.current)b.current.playbackRate=Math.max(.0625,Math.min(16,r*ratio));};
 const setEdge=(edge:'start'|'end',value:number)=>{exitReview();const r=adjustRange({start,end},edge,Math.round(value*1000)/1000,job.media?.duration??0);setStart(r.start);setEnd(r.end);seek(edge==='start'?r.start:Math.max(r.start,r.end-1/(job.media?.fps??30)));};
 useEffect(()=>{const key=(e:KeyboardEvent)=>{const target=e.target as HTMLElement;if(disabled||comparison||e.metaKey||e.ctrlKey||e.altKey||target.closest('input,textarea,select,[contenteditable="true"]'))return;if(e.key.toLowerCase()==='i'||e.key.toLowerCase()==='o'){e.preventDefault();setEdge(e.key.toLowerCase()==='i'?'start':'end',a.current?.currentTime??clock);}};window.addEventListener('keydown',key);return()=>window.removeEventListener('keydown',key);},[disabled,comparison,start,end,clock,job.media?.duration]);
 return <><div ref={viewer} className="viewer-head action-review-anchor"><h2>{comparison?(Math.abs(ratio-1)>.01?'同步对照 · 按动作进度对齐':'同步对照'):'选择参考片段'}</h2>{advanced&&job.outputVersion&&<button onClick={()=>{exitReview();setSource(!source);}}>{source?'回到原片 / 复刻对照':'查看完整原片'}</button>}</div><div className={'viewers '+(!comparison?'single':'')}><div className="viewer"><label>{comparison?'原片 · 参考片段':'原片 · 完整视频'}</label>{job.sourceFile?<video key={job.id+(comparison?'ref'+job.outputVersion:'source')} ref={a} src={api.media(job.id,comparison?'reference.mp4':'source-preview.mp4')+'?v='+job.outputVersion} muted={!sound} preload="metadata" onLoadedMetadata={loaded} onEnded={()=>{if(!review&&!comparison&&loop){seek(start);void a.current?.play().catch(()=>setPlaying(false));}else{setPlaying(false);b.current?.pause();}}}/>:<div className="video-placeholder"><span>▷</span><p>链接和来源已保留<br/>将下载的视频拖进来即可继续</p></div>}</div>{comparison&&<div className="viewer"><label>复刻 · 可编辑预览 <span>静音</span></label><video key={job.outputVersion} ref={b} src={api.media(job.id,'replica.mp4')+'?v='+job.outputVersion} muted preload="metadata"/></div>}</div>
 <div className="transport"><button aria-label="上一帧" onClick={()=>{a.current?.pause();b.current?.pause();setPlaying(false);seek(clock-1/(job.media?.fps??30));}}>Ⅰ◀</button><button className="play" aria-label={playing?'暂停':'播放'} onClick={play}>{playing?'Ⅱ':'▶'}</button><button aria-label="下一帧" onClick={()=>{a.current?.pause();b.current?.pause();setPlaying(false);seek(clock+1/(job.media?.fps??30));}}>▶Ⅰ</button><span className="time">{time(clock)} / {time(duration)}</span><input aria-label="播放位置" type="range" min="0" max={duration||1} step="0.01" value={Math.min(clock,duration)} onChange={e=>scrub(Number(e.target.value))}/><select aria-label="播放速度" value={rate} onChange={e=>setSpeed(Number(e.target.value))}>{[.25,.5,1,1.5].map(n=><option key={n} value={n}>{n}×</option>)}</select><button disabled={!job.media?.audio} onClick={()=>setSound(!sound)}>{sound?'原声开':'原声关'}</button></div>
 {brief&&!!brief.actions.length&&job.sourceFile&&<section className="action-review" aria-label="复看动作">
  <div className="action-review-controls">
   <label>复看动作 <select aria-label="选择要复看的动作" value={reviewIndex??''} onChange={event=>{if(event.target.value==='')exitReview();else previewAction(Number(event.target.value));}}>
    <option value="">选择一条动作</option>
    {brief.actions.map((action,index)=><option key={index} value={index}>{action.element}</option>)}
   </select></label>
   {review&&<><button onClick={()=>previewAction(review.index)}>↻ 重播动作</button><button onClick={exitReview}>退出复看</button></>}
  </div>
  {review&&<div className="action-review-detail">
   <strong>{review.category} · {review.name}</strong>
   <span>原片 {review.start.toFixed(2)}–{review.end.toFixed(2)} 秒{job.author&&` · ${job.author}`}</span>
   <p>{review.note}</p>
  </div>}
 </section>}
 {!comparison&&<><RangeTimeline duration={job.media?.duration??0} start={start} end={end} clock={clock} review={review} disabled={disabled||!job.media} onEdge={setEdge} onSeek={scrub}/><div className="range-shortcuts"><button disabled={disabled||!job.media} onClick={()=>setEdge('start',clock)}>当前画面设为起点 <kbd>I</kbd></button><button disabled={disabled||!job.media} onClick={()=>setEdge('end',clock)}>当前画面设为终点 <kbd>O</kbd></button><button aria-pressed={loop} disabled={!job.media} className={loop?'selected':''} onClick={()=>{exitReview();setLoop(!loop);if(!loop)seek(start);}}>↻ {loop?'循环选段：开':'循环选段：关'}</button><span>{(end-start).toFixed(2)} 秒</span></div><div className="range-editor"><label>从 <input disabled={disabled} aria-label="片段开始秒数" type="number" min="0" step="0.1" value={start} onChange={e=>{exitReview();setStart(Number(e.target.value));}}/> 秒</label><span>—</span><label>到 <input disabled={disabled} aria-label="片段结束秒数" type="number" min="0" step="0.1" value={end} onChange={e=>{exitReview();setEnd(Number(e.target.value));}}/> 秒</label><button disabled={disabled||!job.media} onClick={()=>{exitReview();onSelect({start,end});seek(start);}}>保存范围</button><button className="primary" disabled={disabled||!job.media} onClick={()=>onBrief({start,end})}>{job.brief?.range.start===start&&job.brief?.range.end===end&&!Array.isArray(job.brief.categories)?'重新识别动效':'生成简短动作说明'}</button></div><p className="muted small">建议选 3～10 秒，最多 30 秒。识别选段中的各类动效，使用 Codex 额度；相同片段复用新版结果。导出片段在本机完成。</p></>}
 <QuickBrief key={job.brief?.createdAt} job={job} disabled={disabled} dirty={start!==job.selection?.start||end!==job.selection?.end} onCopy={onCopy} onSaveClips={onSaveClips} onPreview={index=>previewAction(index,true)} activeIndex={reviewIndex}/>
 <div className="editing-export"><div><h3>带到剪映 / 达芬奇继续剪</h3><p>导出所选原片 MP4、动作说明和来源信息；无需先生成工程。保留原声。</p></div><button disabled={disabled||!job.media} onClick={()=>onExport({start,end})}>导出剪辑素材 · 本机</button></div>
 {advanced&&<div className="advanced-panel"><h3>可选：生成可编辑 Remotion 工程</h3><p>会重新细拆、生成代码并渲染，耗时和 Codex 用量较多。已有工程仍在“工程编辑”页。</p><button disabled={disabled||!job.media} onClick={()=>onGenerate({start,end})}>细拆并生成工程</button>{!job.waveform.length&&job.media?.audio&&<button disabled={disabled} onClick={onWaveform}>提取波形 · 本机</button>}</div>}
 {advanced&&!!job.waveform.length&&<div className="wave-section"><div className="viewer-head"><h3>原片波形 <small>点击定位 · 音效落点</small></h3><button disabled={disabled} onClick={()=>onMarkers([...job.markers,comparison?(range?.start??0)+clock:clock])}>＋ 在此标记</button></div><svg viewBox="0 0 1000 64" className="waveform" onClick={e=>{const r=e.currentTarget.getBoundingClientRect();const t=(e.clientX-r.left)/r.width*(job.media?.duration??0);if(source||!comparison)seek(t);else{pendingSeek.current={time:t};setSource(true);}}}>{job.waveform.map((v,i)=><line key={i} x1={i/job.waveform.length*1000} x2={i/job.waveform.length*1000} y1={32-v*28} y2={32+v*28}/>)}{job.markers.map((t,i)=><line key={'m'+i} className="marker" x1={t/(job.media?.duration??1)*1000} x2={t/(job.media?.duration??1)*1000} y1="0" y2="64"/>)}</svg><div className="chips">{job.markers.map((t,i)=><button disabled={disabled} key={i} onClick={()=>onMarkers(job.markers.filter((_,n)=>n!==i))}>{time(t)} ×</button>)}</div></div>}
 {comparison&&job.analysis&&<div className="chips">{job.analysis.events.map((e,i)=><button key={i} onClick={()=>seek(e.time)}>{e.time.toFixed(2)}s · {e.element}</button>)}</div>}
 <div className="viewer-head"><h2>候选片段 <small>初分可能遗漏短动效 · 可直接手填时间</small></h2><button disabled={disabled||!job.media} onClick={onCandidates}>细查全片 · 使用 Codex</button></div><div className="candidates">{job.candidates.map((c,i)=><button className={start===c.start&&end===c.end?'candidate selected':'candidate'} key={i} disabled={disabled} onClick={()=>{exitReview();setSource(true);setStart(c.start);setEnd(c.end);onSelect({start:c.start,end:c.end});}}><div className="candidate-top"><span>0{i+1}</span><b>{time(c.start)} — {time(c.end)}</b><em>{segmentCategories(c).join(' · ')||'待核验'}</em></div><strong>{c.title}</strong><p>{c.reason}</p><small>识别把握：{c.confidence}</small></button>)}</div></>;
}
function QuickBrief({job,disabled,dirty,onCopy,onSaveClips,onPreview,activeIndex}:{job:Job;disabled:boolean;dirty:boolean;onCopy:()=>void;onSaveClips:SaveClips;onPreview:(index:number)=>void;activeIndex?:number}){
 const b=job.brief;
 const match=b&&b.range.start===job.selection?.start&&b.range.end===job.selection?.end&&!dirty;
 const [selected,setSelected]=useState<number[]>([]);
 const [review,setReview]=useState(false);
 const toggle=(index:number)=>setSelected(items=>items.includes(index)?items.filter(item=>item!==index):[...items,index].sort((a,b)=>a-b));
 return <section className="quick-brief">
  <div className="viewer-head">
   <h2>动作说明</h2>
   <div className="brief-buttons">
    <button disabled={disabled||!match} onClick={onCopy}>复制动作说明</button>
    {match&&!!b.actions.length&&<button className="primary" disabled={disabled||review||!selected.length} onClick={()=>setReview(true)}>保存到 Eagle{selected.length?`（${selected.length} 条）`:''}</button>}
   </div>
  </div>
  {match?<>
   {Array.isArray(b.categories)&&<p className="muted small">本段动效：{segmentCategories(b).join(' · ')||'待核验'}</p>}
   <p className="brief-summary">{b.summary}</p>
   {!!b.actions.length&&<p className="muted small">点击时间复看原片，勾选动作可保存到 Eagle。下方时间从当前选段起点算起。</p>}
   {b.actions.map((action,index)=><div className={'brief-line'+(activeIndex===index?' reviewing':'')} key={index}>
    <input id={`choose-action-${index}`} type="checkbox" aria-label={`选择动作 ${action.element}`} checked={selected.includes(index)} disabled={disabled||review} onChange={()=>toggle(index)}/>
    <button className="brief-preview" disabled={!job.sourceFile} aria-label={`复看 ${action.element}`} aria-pressed={activeIndex===index} onClick={()=>onPreview(index)}>▶ {action.start.toFixed(2)}–{action.end.toFixed(2)}s</button>
    <label htmlFor={`choose-action-${index}`}><b>{action.category&&action.category+' · '}{action.element}</b> · {action.motion}</label>
   </div>)}
   {review&&<EagleActionClips brief={b} selected={selected} disabled={disabled} duration={job.media?.duration??0} onLibrary={()=>api.eagleLibrary()} onSave={(library,clips)=>onSaveClips(b.createdAt,library,clips)} onClose={()=>setReview(false)}/>}
   <p className="muted small">节奏理解（推断）：{b.rhythm}</p>
   {b.uncertainty&&<p className="muted small">需核验：{b.uncertainty}</p>}
  </>:<p className="muted">{b?'范围已改变，点击“生成简短动作说明”分析当前片段；旧说明已保留。':'选择几秒，点击“生成简短动作说明”。同时出现的动效会分别列出。'}</p>}
 </section>;
}
function AnalysisView({job,onGenerate,disabled}:{job:Job;onGenerate:()=>void;disabled:boolean}){const a=job.analysis;if(!a)return <div className="tab-empty"><h2>先选择一段你喜欢的动效</h2><p>分析会记录连续帧里真实可见的变化，并单独说明推测。</p><button disabled={disabled||!job.selection} className="primary" onClick={onGenerate}>细拆并生成工程</button></div>;return <div className="analysis"><div className="summary"><span className="eyebrow">{segmentCategories(a).join(' · ')||'待核验'} / {a.supported?'二维复刻':'参考分析'}</span><h2>{a.title}</h2><p>{a.summary}</p><p className="muted">镜头与整体运动：{a.camera}</p></div><h3>为什么看起来顺</h3><div className="insights">{a.smoothness.map((s,i)=><div key={i}><span>0{i+1}</span><p>{s}</p></div>)}</div><h3>动作时间线 <small>时间相对选中片段</small></h3>{a.events.map((e,i)=><div className="event" key={i}><span>{e.time.toFixed(2)}—{e.end.toFixed(2)}s</span><div><strong>{e.category&&e.category+' · '}{e.element} · {e.action}</strong><p><b>观察</b> {e.evidence}</p><p className="muted"><b>推断</b> {e.inference||'无额外推断'}</p></div></div>)}{!!a.limitations.length&&<div className="limitations"><h3>近似与限制</h3>{a.limitations.map((s,i)=><p key={i}>{s}</p>)}</div>}<p className="muted small">这些是画面表达的分析，不代表已经证明它导致了高播放量。</p></div>;}
function Editor({job,disabled,save,render,image,onExport,onEagle}:{job:Job;disabled:boolean;save:(v:any)=>Promise<any>;render:()=>Promise<any>;image:(k:string)=>Promise<any>;onExport:(k:'video'|'project')=>void;onEagle:()=>void}){
 const[draft,setDraft]=useState<Record<string,any>>(job.props??{}),[raw,setRaw]=useState(''),[advanced,setAdvanced]=useState(false),[err,setErr]=useState('');
 useEffect(()=>{setDraft(job.props??{});setRaw(JSON.stringify(job.props??{},null,2));},[JSON.stringify(job.props)]);
 let changed=true;try{changed=JSON.stringify(advanced?JSON.parse(raw):draft)!==job.renderedProps;}catch{}
 if(!job.props)return <div className="tab-empty"><h2>还没有可编辑工程</h2><p>在「选段与动作」中选择时间范围，打开高级复刻，点“细拆并生成工程”。</p></div>;
 const commit=async()=>{setErr('');try{const p=advanced?JSON.parse(raw):draft;await save(p);await render();}catch(e){setErr((e as Error).message);}};
 return <><div className="editor-heading"><div><h2>替换成你的内容</h2><p>修改内容后重新渲染，再到「选段与动作」检查。</p></div><button onClick={()=>{setAdvanced(!advanced);setRaw(JSON.stringify(draft,null,2));}}>{advanced?'常用参数':'全部参数 JSON'}</button></div>{advanced?<textarea className="json-editor" spellCheck={false} aria-label="全部参数" value={raw} onChange={e=>setRaw(e.target.value)}/>:<div className="fields">{job.fields?.map(f=><label key={f.key}>{f.label}{f.type==='image'?<div className="image-field"><span>{String(draft[f.key]||'尚未选择图片')}</span><button disabled={disabled} onClick={async()=>{setErr('');try{await save(advanced?JSON.parse(raw):draft);await image(f.key);}catch(e){setErr((e as Error).message);}}}>选择图片</button></div>:<input aria-label={f.label} type={f.type==='color'?'color':f.type==='number'?'number':'text'} step={f.type==='number'?'any':undefined} value={draft[f.key]??''} onChange={e=>setDraft({...draft,[f.key]:f.type==='number'?Number(e.target.value):e.target.value})}/>}</label>)}</div>}{err&&<p className="error">{err}</p>}<button className="primary" disabled={disabled} onClick={()=>void commit()}>{changed?'保存参数并重新渲染':'重新渲染预览'}</button><div className="export-card"><h3>带走你的镜头</h3><p>MP4 默认静音。修改参数后请先渲染，导出才会包含新内容。工程保留来源记录。</p><div><button disabled={disabled||!job.outputVersion||changed} onClick={()=>onExport('video')}>导出 MP4</button><button disabled={disabled} onClick={()=>onExport('project')}>导出可编辑工程</button><button disabled={disabled||!job.outputVersion||changed} onClick={onEagle}>保存到 Eagle</button></div>{job.eagle&&<small className="green">已导入 Eagle 并核对素材记录</small>}</div></>;
}
function Metadata({job,disabled,save}:{job:Job;disabled:boolean;save:(v:unknown)=>void}){const[d,setD]=useState({...job.metrics,title:job.title,author:job.author});const field=(k:string,v:any)=>setD({...d,[k]:v});return <div className="metadata"><h2>来源与表现数据</h2><p>数据缺失保持空白。选择相同口径后，才能按播放量或点赞量排序。</p><div className="fields"><label>视频标题<input value={d.title} onChange={e=>field('title',e.target.value)}/></label><label>作者<input value={d.author} onChange={e=>field('author',e.target.value)}/></label>{(['views','likes'] as const).map(k=><label key={k}>{k==='views'?'播放量':'点赞量'}<input type="number" min="0" placeholder="未获取" value={d[k]??''} onChange={e=>field(k,e.target.value===''?null:Number(e.target.value))}/></label>)}<label>数据口径<select value={d.scope} onChange={e=>field('scope',e.target.value)}>{['未知','单条视频实测','账号汇总','预期播放量'].map(s=><option key={s}>{s}</option>)}</select></label><label>流量口径<select value={d.traffic} onChange={e=>field('traffic',e.target.value)}>{['未知','全部','非营销'].map(s=><option key={s}>{s}</option>)}</select></label><label>发布日期<input placeholder="例如 2026-11-12" value={d.published} onChange={e=>field('published',e.target.value)}/></label><label>数据来源<input placeholder="手工补录 · 星图页面" value={d.source} onChange={e=>field('source',e.target.value)}/></label></div><button className="primary" disabled={disabled} onClick={()=>save(d)}>保存来源数据</button><div className="source-info"><p>来源链接：{job.sourceUrl||'本地导入'}</p><p>原始文件：{job.originalPath||'链接下载'}</p><p>采集时间：{job.metrics.captured||'未获取'}</p><p>当前播放 {metric(job.metrics.views)} · 点赞 {metric(job.metrics.likes)}</p></div></div>;}
createRoot(document.getElementById('root')!).render(<App/>);
