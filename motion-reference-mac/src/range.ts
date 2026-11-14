export type ClipRange={start:number;end:number};
// Moving either handle keeps the selected range valid, including at the end
// of short videos. Numerical entry remains available for exact timestamps.
export function adjustRange(range:ClipRange,edge:'start'|'end',value:number,duration:number):ClipRange {
 if(!Number.isFinite(duration)||duration<.2)return {start:0,end:Math.max(0,duration||0)};
 const v=Math.max(0,Math.min(duration,Number.isFinite(value)?value:0));
 if(edge==='start'){
  const start=Math.min(duration-.2,v);
  const end=Math.min(duration,Math.max(start+.2,Math.min(range.end,start+30)));
  return {start,end};
 }
 const end=Math.max(.2,v);
 const start=Math.max(0,Math.min(end-.2,Math.max(range.start,end-30)));
 return {start,end};
}
