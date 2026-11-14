import {createHash} from 'node:crypto';
import type {Job,Brief} from './types';
import {normalizeCategories,segmentCategories} from './motion-categories';

// The key identifies the saved clip. Older briefs remain readable and can be analyzed again.
export const briefKey=(job:Job,range:{start:number;end:number})=>createHash('sha256').update(JSON.stringify(['brief-v1',job.sha256??job.id,range])).digest('hex').slice(0,24);
export function matchingBrief(job:Job):Brief|undefined {return job.selection&&job.brief?.key===briefKey(job,job.selection)?job.brief:undefined;}
export function briefText(job:Job){
 const b=matchingBrief(job),r=job.selection;
 const types=Array.isArray(b?.categories)?segmentCategories(b):normalizeCategories([job.classification?.primary,...(job.classification?.secondary??[])]);
 return [
  `素材：${job.title}`,`类别：${types.join(' · ')||'待分类'}`,`作者：${job.author||'待补充'}`,`来源：${job.sourceUrl||'本地视频'}`,`原片范围：${r?.start??0}～${r?.end??0} 秒`,
  '',b?'动作说明（时间相对选中片段）':'尚未进行 AI 分析；此导出仅作剪辑参考。',
  ...(b?[b.summary,...b.actions.map(a=>`${a.start.toFixed(2)}～${a.end.toFixed(2)} 秒｜${a.category?`[${a.category}] `:''}${a.element}：${a.motion}`),`节奏理解（推断）：${b.rhythm}`,`不确定之处：${b.uncertainty||'未额外标记；节点仍需播放核对'}`]:[]),
  '',`我的标注：${job.classification?.note||'无'}`,
  ...(b?['','给 GPT 的任务：依据以上动作说明和参考片段，说明如何用位置、缩放、旋转、透明度等关键帧实现相似运动。保留动作先后、方向和停顿，用我的文字与图片替换内容；不确定的细节先指出。']:[]),
 ].join('\n');
}
