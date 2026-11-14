import type {LinkMode,SearchPlatform} from './reference-links';
export type Stage = '读取视频'|'分类标注'|'找候选'|'拆解'|'生成'|'渲染'|'对照';
export type State = 'idle'|'queued'|'running'|'ready'|'failed'|'cancelled'|'interrupted';
export const categories = ['单张','多张','PNG','文献','通屏','边框','标题','关键词','图表'] as const;
export type Category = typeof categories[number];
export const taxonomy = [
 {group:'图片',items:[{name:'单张',description:'一张照片或产品图承载主要信息'},{name:'多张',description:'多张图片、卡片并列、层叠或展开'},{name:'PNG',description:'抠图、独立图标与图形叠加；不代表原文件格式'},{name:'文献',description:'论文、报告、书页、新闻或资料截图'}]},
 {group:'视频',items:[{name:'通屏',description:'视频画面铺满内容区域'},{name:'边框',description:'视频置于边框、窗口或画中画中'}]},
 {group:'文字',items:[{name:'标题',description:'片头、章节标题与主标题呈现'},{name:'关键词',description:'强调关键词、数字或短语'}]},
 {group:'图表',items:[{name:'图表',description:'柱形、折线等数据与结构关系可视化'}]},
] as const;
export const categoryGroup=(name:string)=>taxonomy.find(g=>g.items.some(i=>i.name===name))?.group??'待分类';
export interface Classification {primary:Category|'待分类';secondary:Category[];reason:string;note:string;authorEvidence:string;authorSource:string;confirmedAt?:number}
// Saved candidates and analyses from older versions can have a single category.
export interface SegmentCategories {categories?:Category[];category?:string}
export interface Candidate extends SegmentCategories {start:number; end:number; title:string; reason:string; confidence:string}
export interface MotionEvent {time:number; end:number; element:string; action:string; evidence:string; inference:string; category?:Category}
export interface Analysis extends SegmentCategories {title:string; summary:string; supported:boolean; limitations:string[]; smoothness:string[]; camera:string; events:MotionEvent[]}
export interface Brief {key:string;range:{start:number;end:number};createdAt:number;summary:string;categories?:Category[];actions:{start:number;end:number;element:string;motion:string;category?:Category}[];rhythm:string;uncertainty:string}
export interface MotionClipDraft {
 index:number;
 start:number;
 end:number;
 name:string;
 category:Category|'待分类';
 note:string;
}
export interface EagleClipResult {library:string;saved:number}
export interface Media {duration:number; width:number; height:number; fps:number; audio:boolean;videoCodec?:string;audioCodec?:string}
export interface Metrics {views:number|null; likes:number|null; published:string; captured:string; scope:'单条视频实测'|'账号汇总'|'预期播放量'|'未知'; traffic:'全部'|'非营销'|'未知'; source:string}
export interface Field {key:string; label:string; type:'text'|'number'|'color'|'image'; min?:number; max?:number}
export interface Progress {stage:Stage; state:State; detail:string; done?:number; total?:number; startedAt:number; stageAt:number; updatedAt:number; finishedAt?:number; queuedAt?:number; queuePosition?:number; estimate?:[number,number]}
export interface Job {referenceKind?:'account';searchPlatform?:SearchPlatform;id:string; title:string; createdAt:number; sourceUrl:string; author:string; classification?:Classification; overviewCategories?:Category[]; originalPath?:string; sourceFile?:string; sha256?:string; metrics:Metrics; media?:Media; candidates:Candidate[]; selection?:{start:number;end:number}; referenceRange?:{start:number;end:number}; analysis?:Analysis; brief?:Brief; waveform:number[]; markers:number[]; props?:Record<string,unknown>; fields?:Field[]; outputVersion?:number; renderedProps?:string; timings?:{stage:Stage;seconds:number;action?:string}[]; progress:Progress; error?:string; logs:{at:number;text:string}[]; eagle?:{library:string;itemId?:string}; pendingAction?:'import'|'download'|'candidates'|'generate'|'render'|'brief'|'export'|'eagle-clips'|'waveform'}
export interface Environment {codex:boolean; signedIn:boolean; plan?:string; ffmpeg:boolean; downloader:boolean; dataDir:string; error?:string}
export interface LinkSubmission {jobs: Job[]; added: number; existing: number; queued: number}
export type SearchHistoryEntries = Record<SearchPlatform, string[]>;
export interface InstalledTool {name: string; path: string}
export interface RecorderControls {
 recording: 'idle' | 'starting' | 'recording' | 'busy';
 canScreenshot: boolean;
 unifiedShelf: boolean;
}
export type CaptureAction = 'record' | 'screenshot' | 'shelf' | 'settings';
export interface CaptureTool {
 status: 'ready' | 'starting' | 'stopped' | 'missing';
 controls?: RecorderControls;
}
export interface ToolBookmark {name: string; url: string}
export interface TrackpadStatus {
 state: 'ready' | 'locking' | 'locked' | 'unlocking' | 'recovery' | 'unavailable';
 shortcut: string | null;
 warning: string | null;
}
export interface KeyboardStatus {
 state: TrackpadStatus['state'];
 external: boolean;
 permission: boolean;
 warning: string | null;
 f3: boolean;
 f3Warning: string | null;
 f4: boolean;
 f4Warning: string | null;
 f4Supported: boolean;
 f4Permission: boolean;
}
export interface Bridge {
 keyboardStatus(): Promise<KeyboardStatus>;
 setKeyboardLocked(locked: boolean): Promise<KeyboardStatus>;
 setF3RecordingShortcut(enabled: boolean): Promise<KeyboardStatus>;
 setF4ForceQuitShortcut(enabled: boolean): Promise<KeyboardStatus>;
 requestF4ForceQuitPermission(): Promise<KeyboardStatus>;
 requestKeyboardPermission(): Promise<KeyboardStatus>;
 trackpadStatus(): Promise<TrackpadStatus>;
 setTrackpadLocked(locked: boolean): Promise<TrackpadStatus>;
 captureStatus(): Promise<CaptureTool>;
 startCapture(): Promise<CaptureTool>;
 controlRecorder(action: CaptureAction): Promise<void>;
 installedTools(): Promise<InstalledTool[]>;
 openTool(path:string): Promise<void>;
 searchTools(keyword:string): Promise<void>;
 toolBookmarks(): Promise<ToolBookmark[]>;
 saveToolBookmark(name:string,url:string): Promise<ToolBookmark[]>;
 openToolBookmark(url:string): Promise<void>;
 removeToolBookmark(url:string): Promise<ToolBookmark[]>;
 readLinkClipboard(): Promise<string>;
 submitLinks(text:string,mode:LinkMode): Promise<LinkSubmission>;
 saveAccount(name:string,platform:SearchPlatform): Promise<Job>;
 searchHistory(): Promise<SearchHistoryEntries>;
 searchReferences(platform:SearchPlatform,keyword:string): Promise<SearchHistoryEntries>;
 attachVideo(id:string): Promise<Job|null>;
 eagleLibrary():Promise<string>;
 saveActionClips(id:string,briefCreatedAt:number,library:string,clips:MotionClipDraft[]):Promise<EagleClipResult>;
 authors():Promise<string[]>; addAuthor(name:string):Promise<string[]>; copyBrief(id:string):Promise<void>; list():Promise<Job[]>; environment():Promise<Environment>; pickVideo():Promise<Job[]|null>; importVideo(path:string,attachTo?:string):Promise<Job>;
 action(id:string,action:string,data?:unknown):Promise<Job>; image(id:string,key:string):Promise<Job|null>; export(id:string,kind:'video'|'project'|'editing'):Promise<string|null>;
 reveal(id:string):Promise<void>; openSource(id:string):Promise<void>; filePath(file:File):string; media(id:string,path:string):string; subscribe(fn:(job:Job)=>void):()=>void;
}
