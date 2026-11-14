import {setTimeout as delay} from 'node:timers/promises';

interface EagleFolder {id:string;name:string;children?:EagleFolder[]}
interface EagleItem {id:string;annotation?:string;isDeleted?:boolean}

export async function eagleRequest<T>(route:string,body?:unknown):Promise<T> {
 const response=await fetch('http://127.0.0.1:41595/api/'+route,{
  method:body===undefined?'GET':'POST',
  headers:body===undefined?undefined:{'Content-Type':'application/json'},
  body:body===undefined?undefined:JSON.stringify(body),
  signal:AbortSignal.timeout(10_000),
 }).catch(()=>{throw new Error('Eagle 未运行或本地接口不可用，请打开 Eagle 后重试');});
 const result=await response.json();
 if(!response.ok||result.status!=='success')throw new Error(result.message??'Eagle 操作未成功');
 return result.data;
}

export async function eagleLibrary():Promise<string> {
 const info=await eagleRequest<{library?:{path?:string};libraryPath?:string;path?:string}>('library/info');
 const path=info.library?.path??info.libraryPath??info.path;
 if(!path)throw new Error('请先在 Eagle 中打开要保存的资源库');
 return path;
}

export async function checkEagleLibrary(expected:string) {
 if(await eagleLibrary()!==expected)throw new Error('Eagle 资源库已切换，请刷新保存位置后重试');
}

const pendingFolders=new Map<string,Promise<string>>();

export function eagleMotionFolder(library:string):Promise<string> {
 const pending=pendingFolders.get(library);
 if(pending)return pending;
 const folder=findOrCreateMotionFolder(library).finally(()=>pendingFolders.delete(library));
 pendingFolders.set(library,folder);
 return folder;
}

async function findOrCreateMotionFolder(library:string) {
 await checkEagleLibrary(library);
 const folders=await eagleRequest<EagleFolder[]>('folder/list');
 const find=(list:EagleFolder[]):EagleFolder|undefined=>{
  for(const folder of list){
   if(folder.name==='动效拆解')return folder;
   const child=find(folder.children??[]);
   if(child)return child;
  }
 };
 const existing=find(folders);
 if(existing)return existing.id;
 await checkEagleLibrary(library);
 return (await eagleRequest<EagleFolder>('folder/create',{folderName:'动效拆解'})).id;
}

export async function eagleClipExists(library:string,folderId:string,marker:string,signal:AbortSignal,attempts=1) {
 for(let i=0;i<attempts;i++){
  signal.throwIfAborted();
  await checkEagleLibrary(library);
  const items=await eagleRequest<EagleItem[]>('item/list?ext=mp4&limit=10000&folders='+encodeURIComponent(folderId));
  if(items.some(item=>!item.isDeleted&&item.annotation?.split('\n').includes(marker)))return true;
  if(i+1<attempts)await delay(500,undefined,{signal});
 }
 return false;
}
