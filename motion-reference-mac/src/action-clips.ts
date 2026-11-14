import type {Brief,MotionClipDraft} from './types';

const roundSeconds=(seconds:number)=>Math.round(seconds*1000)/1000;

export function actionClipDraft(brief:Brief,index:number):MotionClipDraft {
 const action=brief.actions[index];
 const start=roundSeconds(brief.range.start+action.start);
 const end=roundSeconds(brief.range.start+action.end);
 return {
  index,start,end,
  name:action.element,
  category:action.category??'待分类',
  note:action.motion,
 };
}
