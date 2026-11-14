import React,{useEffect,useRef,useState} from 'react';
import {actionClipDraft} from '../action-clips';
import {categories,type Brief,type EagleClipResult,type MotionClipDraft} from '../types';

export function EagleActionClips({brief,selected,disabled,duration,onLibrary,onSave,onClose}:{
 brief:Brief;
 selected:number[];
 disabled:boolean;
 duration:number;
 onLibrary:()=>Promise<string>;
 onSave:(library:string,drafts:MotionClipDraft[])=>Promise<EagleClipResult>;
 onClose:()=>void;
}){
 const [clips,setClips]=useState(()=>selected.map(index=>actionClipDraft(brief,index)));
 const [library,setLibrary]=useState('');
 const [loading,setLoading]=useState(true);
 const [error,setError]=useState('');
 const [saving,setSaving]=useState(false);
 const panel=useRef<HTMLElement>(null);
 const refresh=async()=>{
  setError('');
  setLibrary('');
  setLoading(true);
  try{setLibrary(await onLibrary());}
  catch(error){setError((error as Error).message);}
  finally{setLoading(false);}
 };
 useEffect(()=>{panel.current?.scrollIntoView({block:'nearest'});void refresh();},[]);
 const update=(index:number,patch:Partial<MotionClipDraft>)=>setClips(items=>items.map(clip=>clip.index===index?{...clip,...patch}:clip));
 const invalid=clips.some(clip=>!clip.name.trim()||!Number.isFinite(clip.start)||!Number.isFinite(clip.end)||clip.start<0||clip.end>duration+.001||clip.end-clip.start<.2-1e-9||clip.end-clip.start>30+1e-9);
 const save=async()=>{
  setError('');
  setSaving(true);
  try{await onSave(library,clips);onClose();}
  catch(error){setError((error as Error).message.replace(/^Error invoking remote method '[^']+': Error: /,''));}
  finally{setSaving(false);}
 };
 return <section ref={panel} className="action-clip-panel" aria-label="核对 Eagle 片段">
  <div className="viewer-head">
   <h3>保存 {clips.length} 条到 Eagle</h3>
   <button disabled={saving} onClick={onClose}>关闭</button>
  </div>
  <div className="eagle-destination">
   <p className="muted small">{loading?'正在读取 Eagle 资源库…':library?`资源库 ${library} → 动效拆解`:'请在 Eagle 中打开要保存的资源库。'}</p>
   <button disabled={saving||loading} onClick={()=>void refresh()}>刷新保存位置</button>
  </div>
  <p className="muted small">以下时间对应完整录屏。每条保存为独立 MP4，保留原声和同屏画面。</p>
  {clips.map((clip,i)=><fieldset key={clip.index} disabled={saving||disabled}>
   <legend>片段 {i+1}</legend>
   <div className="action-clip-fields">
    <label>名称<input value={clip.name} maxLength={120} onChange={e=>update(clip.index,{name:e.target.value})}/></label>
    <label>类型<select value={clip.category} onChange={e=>update(clip.index,{category:e.target.value as MotionClipDraft['category']})}>{['待分类',...categories].map(type=><option key={type}>{type}</option>)}</select></label>
    <label>起点（秒）<input type="number" min="0" max={duration} step=".001" value={Number.isFinite(clip.start)?clip.start:''} onChange={e=>update(clip.index,{start:e.target.valueAsNumber})}/></label>
    <label>终点（秒）<input type="number" min="0" max={duration} step=".001" value={Number.isFinite(clip.end)?clip.end:''} onChange={e=>update(clip.index,{end:e.target.valueAsNumber})}/></label>
   </div>
   <label>动作备注<textarea rows={2} maxLength={1000} value={clip.note} onChange={e=>update(clip.index,{note:e.target.value})}/></label>
  </fieldset>)}
  {invalid&&<p role="status" className="muted small">请填写名称，并将每条片段设在原片内，时长 0.2～30 秒。</p>}
  {error&&<p role="alert" className="error">{error}</p>}
  <button className="primary" disabled={saving||disabled||invalid||!library} onClick={()=>void save()}>{saving?'正在裁剪并保存…':'确认保存到 Eagle'}</button>
 </section>;
}
