import {app,BrowserWindow,ipcMain,dialog,shell,protocol,Menu,clipboard} from 'electron';
import path from 'node:path';
import fs from 'node:fs/promises';
import {createReadStream, mkdirSync} from 'node:fs';
import {Readable} from 'node:stream';
import {Engine} from './engine';
import {publicURL} from './core';
import {searchTarget} from './reference-links';
import {SearchHistory} from './search-history';
import {captureStatus, controlRecorder, installedTools, ToolBookmarks} from './workbench';
import {briefText,matchingBrief} from './brief';
import {eagleLibrary} from './eagle';
import {TrackpadController} from './trackpad';

protocol.registerSchemesAsPrivileged([{scheme:'motion',privileges:{standard:true,secure:true,supportFetchAPI:true,stream:true}}]);
const dataDirectory = path.join(app.getPath('appData'), '动效拆解');
app.setName('创作工作台');
mkdirSync(dataDirectory,{recursive:true});
app.setPath('userData',dataDirectory);
let window:BrowserWindow|undefined,engine:Engine,quitting=false;
if(!app.requestSingleInstanceLock())app.quit();
app.on('second-instance',()=>{window?.show();window?.focus();});
app.on('before-quit',event=>{if(engine&&!quitting){event.preventDefault();quitting=true;void engine.shutdown().finally(()=>app.quit());}});
app.whenReady().then(async()=>{
 engine = new Engine(dataDirectory, app.getAppPath());
 await engine.init();
 const searchHistory = new SearchHistory(path.join(dataDirectory, 'search-history.json'));
 protocol.handle('motion',async request=>{
  try{const url=new URL(request.url);const file=await engine.asset(url.hostname,decodeURIComponent(url.pathname.slice(1)));const st=await fs.stat(file);let start=0,end=st.size-1,status=200;const range=request.headers.get('range');
   if(range){const m=/^bytes=(\d*)-(\d*)$/.exec(range);if(!m)return new Response(null,{status:416});if(m[1]){start=Number(m[1]);if(m[2])end=Math.min(Number(m[2]),end);}else if(m[2])start=Math.max(0,st.size-Number(m[2]));else return new Response(null,{status:416});status=206;}
   if(start>end||start>=st.size)return new Response(null,{status:416,headers:{'Content-Range':`bytes */${st.size}`}});
   const headers:Record<string,string>={'Content-Type':file.endsWith('.jpg')?'image/jpeg':'video/mp4','Content-Length':String(end-start+1),'Accept-Ranges':'bytes','Cache-Control':'no-store'};if(status===206)headers['Content-Range']=`bytes ${start}-${end}/${st.size}`;
   return new Response(Readable.toWeb(createReadStream(file,{start,end})) as any,{status,headers});
  }catch{return new Response('Not found',{status:404});}
 });
 const handle=(name:string,fn:(...a:any[])=>any)=>ipcMain.handle(name,async(event,...args)=>{if(event.sender!==window?.webContents||event.senderFrame!==window.webContents.mainFrame)throw new Error('不允许的调用');return fn(...args);});
 const bookmarks = new ToolBookmarks(path.join(dataDirectory,'tool-bookmarks.json'));
 const startingCaptures = captureStatus(true).catch(() => undefined);
 const home = app.getPath('home');
 const trackpad = new TrackpadController([
  path.join(home, 'Applications', '触控板锁.app'),
  path.join(app.isPackaged ? process.resourcesPath : path.join(app.getAppPath(), '.cache', 'embedded'), 'Trackpad', '触控板锁.app'),
 ], home);
 handle('workbench:keyboard-status', () => trackpad.keyboard());
 handle('workbench:keyboard-permission', () => trackpad.keyboard('keyboard-permission'));
 handle('workbench:keyboard-set', (locked: unknown) => {
  if (typeof locked !== 'boolean') throw new Error('无效的键盘开关状态');
  return trackpad.keyboard(locked ? 'keyboard-lock' : 'keyboard-unlock');
 });
 handle('workbench:f3-set', (enabled: unknown) => {
  if (typeof enabled !== 'boolean') throw new Error('无效的 F3 开关状态');
  return trackpad.keyboard(enabled ? 'f3-on' : 'f3-off');
 });
 handle('workbench:f4-permission', () => trackpad.keyboard('f4-permission'));
 handle('workbench:f4-set', (enabled: unknown) => {
  if (typeof enabled !== 'boolean') throw new Error('无效的 F4 开关状态');
  return trackpad.keyboard(enabled ? 'f4-on' : 'f4-off');
 });
 handle('workbench:trackpad-status', () => trackpad.status());
 handle('workbench:trackpad-set', (locked: unknown) => {
  if (typeof locked !== 'boolean') throw new Error('无效的触控板开关状态');
  return trackpad.setLocked(locked);
 });
 const openApplication = async (appPath: string) => {
  const error = await shell.openPath(appPath);
  if (error) throw new Error(error);
 };
 handle('workbench:captures', async () => {
  await startingCaptures;
  return captureStatus();
 });
 handle('workbench:recorder-control', (action: unknown) => {
  if (action !== 'record' && action !== 'screenshot' && action !== 'shelf' && action !== 'settings') {
   throw new Error('未知的截录暂存操作');
  }
  return controlRecorder(action);
 });
 handle('workbench:start-capture', () => captureStatus(true));
 handle('workbench:installed', () => installedTools());
 handle('workbench:open-app', async appPath => {
  if (!(await installedTools()).some(application => application.path === appPath)) throw new Error('找不到这个应用');
  await openApplication(appPath);
 });
 handle('workbench:search', async keyword => {
  const term = typeof keyword === 'string' ? keyword.trim().slice(0,120) : '';
  if (!term) throw new Error('请输入工具名称');
  const url = new URL('https://cn.bing.com/search');
  url.searchParams.set('q',term);
  await shell.openExternal(url.href);
 });
 handle('workbench:bookmarks', () => bookmarks.list());
 handle('workbench:save-bookmark', (name,url) => bookmarks.save(name,url));
 handle('workbench:open-bookmark', async url => {
  if (!(await bookmarks.list()).some(item => item.url === url)) throw new Error('找不到这个收藏');
  await shell.openExternal(publicURL(url));
 });
 handle('workbench:remove-bookmark', url => bookmarks.remove(url));
 handle('eagle:library',()=>eagleLibrary());
 handle('eagle:action-clips',(id,createdAt,library,clips)=>engine.saveActionClips(id,createdAt,library,clips));
 handle('authors:list',()=>engine.authors.list());handle('authors:add',name=>engine.authors.add(name));handle('brief:copy',async id=>{const job=await engine.store.get(id);if(!matchingBrief(job))throw new Error('先生成当前片段的动作说明');clipboard.writeText(briefText(job));});
 handle('jobs:list',()=>engine.store.list());handle('environment',()=>engine.environment());
 handle('video:pick',async()=>{const r=await dialog.showOpenDialog(window!,{title:'选择参考视频',properties:['openFile','multiSelections'],filters:[{name:'视频',extensions:['mp4','mov','webm','m4v']}]});if(r.canceled)return null;const jobs=[];for(const file of r.filePaths)jobs.push(await engine.importVideo(file));return jobs;});
 handle('reference:clipboard', async () => (await clipboard.readText()).slice(0,20_000));
 handle('reference:submit', (text,mode) => engine.submitLinks(text,mode));
 handle('reference:account', (name,platform) => engine.saveAccount(name,platform));
 handle('reference:history', () => searchHistory.list());
 handle('reference:search', async (platform,keyword) => {
  const target = searchTarget(platform,keyword);
  if (target) {
   const history = await searchHistory.record(platform,keyword);
   await shell.openExternal(target);
   return history;
  }
  await clipboard.writeText(keyword.trim().slice(0,120));
  const history = await searchHistory.record(platform,keyword);
  // The copied keyword also works if WeChat is installed in another location.
  await shell.openPath('/Applications/WeChat.app');
  return history;
 });
 handle('reference:attach', async id => {
  const selection = await dialog.showOpenDialog(window!, {
   title:'选择要关联的本地视频',properties:['openFile'],
   filters:[{name:'视频',extensions:['mp4','mov','webm','m4v']}],
  });
  return selection.canceled ? null : engine.importVideo(selection.filePaths[0],id);
 });
 handle('video:import',(file,id)=>engine.importVideo(file,id));handle('job:action',(id,action,data)=>engine.action(id,action,data));
 handle('job:image',async(id,key)=>{const r=await dialog.showOpenDialog(window!,{title:'替换图片',properties:['openFile'],filters:[{name:'图片',extensions:['png','jpg','jpeg','webp']}]});return r.canceled?null:engine.image(id,key,r.filePaths[0]);});
 handle('job:export',async(id,kind)=>{if(!['video','project','editing'].includes(kind))throw new Error('未知导出类型');const job=await engine.store.get(id);const r=await dialog.showOpenDialog(window!,{title:kind==='editing'?'选择剪辑素材保存目录':kind==='video'?'选择 MP4 保存目录':'选择可编辑工程保存目录',properties:['openDirectory','createDirectory']});if(r.canceled)return null;const name=(job.analysis?.title??job.title).replace(/[/:\\]/g,'_').slice(0,100)||'动效';let n=1;let target:string;do{target=path.join(r.filePaths[0],name+(n===1?'':` (${n})`)+(kind==='video'?'.mp4':kind==='editing'?'_剪辑素材':'_可编辑工程'));n++;}while(await fs.access(target).then(()=>true).catch(()=>false));await (kind==='editing'?engine.exportEditing(id,target):kind==='video'?engine.exportVideo(id,target):engine.exportProject(id,target));shell.showItemInFolder(target);return target;});
 handle('job:reveal',id=>shell.openPath(engine.store.dir(id)));handle('job:source',async id=>{const j=await engine.store.get(id);if(j.sourceUrl)await shell.openExternal(publicURL(j.sourceUrl));});
 const create=()=>{
  window=new BrowserWindow({title:'创作工作台',width:1400,height:940,minWidth:1100,minHeight:720,backgroundColor:'#101113',titleBarStyle:'hiddenInset',trafficLightPosition:{x:20,y:20},webPreferences:{preload:path.join(__dirname,'preload.cjs'),contextIsolation:true,nodeIntegration:false,sandbox:true}});
  window.webContents.setWindowOpenHandler(()=>({action:'deny'}));window.webContents.on('will-navigate',e=>e.preventDefault());window.webContents.session.setPermissionRequestHandler((_w,_p,callback)=>callback(false));window.loadFile(path.join(__dirname,'index.html'));
  window.on('closed',()=>{window=undefined;});
 };
 engine.on('job',job=>window?.webContents.send('job:update',job));
 Menu.setApplicationMenu(Menu.buildFromTemplate([{label:'创作工作台',submenu:[{role:'about'},{type:'separator'},{role:'hide'},{role:'hideOthers'},{type:'separator'},{role:'quit'}]},{label:'编辑',submenu:[{role:'undo'},{role:'redo'},{type:'separator'},{role:'cut'},{role:'copy'},{role:'paste'},{role:'selectAll'}]},{label:'窗口',submenu:[{role:'minimize'},{role:'zoom'},{role:'front'}]}]));
 create();app.on('activate',()=>{if(!window)create();else window.show();});
});
