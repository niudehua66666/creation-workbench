import React,{useRef} from 'react';

export function RangeTimeline({duration,start,end,clock,review,disabled,onEdge,onSeek}:{duration:number;start:number;end:number;clock:number;review?:{start:number;end:number};disabled:boolean;onEdge:(edge:'start'|'end',value:number)=>void;onSeek:(value:number)=>void}){
 const percent=(t:number)=>Math.max(0,Math.min(100,t/(duration||1)*100));
 const track=useRef<HTMLDivElement>(null),drag=useRef<{edge:'start'|'end';pointer:number}|null>(null);
 const move=(e:React.PointerEvent<HTMLInputElement>)=>{const active=drag.current,box=track.current?.getBoundingClientRect();if(!active||!box||active.pointer!==e.pointerId)return;onEdge(active.edge,Math.round(Math.max(0,Math.min(duration,(e.clientX-box.left)/box.width*duration))*1000)/1000);};
 const handle=(edge:'start'|'end')=>({
  onPointerDown:(e:React.PointerEvent<HTMLInputElement>)=>{if(disabled)return;e.preventDefault();e.currentTarget.focus();e.currentTarget.setPointerCapture(e.pointerId);drag.current={edge,pointer:e.pointerId};},
  onPointerMove:move,
  onPointerUp:(e:React.PointerEvent<HTMLInputElement>)=>{move(e);drag.current=null;if(e.currentTarget.hasPointerCapture(e.pointerId))e.currentTarget.releasePointerCapture(e.pointerId);},
  onPointerCancel:()=>{drag.current=null;},
 });
 return <section className={'clip-timeline '+(disabled?'disabled':'')} aria-label="片段时间轴">
  <div className="timeline-labels"><strong>拖动两端选择片段</strong><span>0.2–30 秒 · 点击轨道定位</span></div>
  <div ref={track} className="timeline-track" onPointerDown={e=>{if(e.target!==e.currentTarget||disabled||!duration)return;const box=e.currentTarget.getBoundingClientRect();onSeek((e.clientX-box.left)/box.width*duration);}}>
   <div className="timeline-selection" style={{left:percent(start)+'%',width:Math.max(0,percent(end)-percent(start))+'%'}}/>
   {review&&<div className="timeline-review" aria-hidden="true" style={{left:percent(review.start)+'%',width:Math.max(0,percent(review.end)-percent(review.start))+'%'}}/>}
   <div className="timeline-playhead" style={{left:percent(clock)+'%'}}/>
   <input {...handle('start')} aria-label="拖动片段起点" type="range" min="0" max={duration||1} step="0.001" value={start} disabled={disabled||duration<.2} onChange={e=>{if(!drag.current)onEdge('start',Number(e.target.value));}}/>
   <input {...handle('end')} aria-label="拖动片段终点" type="range" min="0" max={duration||1} step="0.001" value={end} disabled={disabled||duration<.2} onChange={e=>{if(!drag.current)onEdge('end',Number(e.target.value));}}/>
  </div>
  <div className="timeline-ticks"><span>0:00</span><b>{start.toFixed(2)} s — {end.toFixed(2)} s</b><span>{Math.floor(duration/60)}:{Math.floor(duration%60).toString().padStart(2,'0')}</span></div>
 </section>;
}
