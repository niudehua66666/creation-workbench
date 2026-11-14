import {categories} from './types';

const str={type:'string'},num={type:'number'},bool={type:'boolean'};
const array=(items:any)=>({type:'array',items});
const obj=(properties:Record<string,unknown>)=>({type:'object',additionalProperties:false,required:Object.keys(properties),properties});
const category={type:'string',enum:categories};
const categoryOrUnknown={type:'string',enum:[...categories,'待分类']};
export const candidateSchema=obj({classification:obj({primary:categoryOrUnknown,secondary:array(category),reason:str,suggestedAuthor:str,authorEvidence:str}),candidates:array(obj({start:num,end:num,title:str,reason:str,categories:array(category),confidence:str}))});
export const analysisSchema=obj({title:str,categories:array(category),summary:str,supported:bool,limitations:array(str),smoothness:array(str),camera:str,events:array(obj({time:num,end:num,element:str,action:str,evidence:str,inference:str,category:categoryOrUnknown}))});
export const generationSchema=obj({code:str,propsJSON:str,fields:array(obj({key:str,label:str,type:{type:'string',enum:['text','number','color','image']}})),notes:array(str)});

export const briefSchema=obj({summary:str,categories:array(category),actions:array(obj({start:num,end:num,element:str,motion:str,category:categoryOrUnknown})),rhythm:str,uncertainty:str});
