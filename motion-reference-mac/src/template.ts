import fs from 'node:fs/promises';
import path from 'node:path';
import ts from 'typescript';
import type {Field} from './types';
export function validateScene(code:string){
 if(code.length>100_000)throw new Error('生成代码过长');
 const tree=ts.createSourceFile('Scene.tsx',code,ts.ScriptTarget.Latest,true,ts.ScriptKind.TSX);
 const banned=new Set(['require','eval','Function','process','global','globalThis','window','document','fetch','XMLHttpRequest','WebSocket','Worker','SharedWorker','importScripts','localStorage','sessionStorage','navigator','location','setTimeout','setInterval','Video','OffthreadVideo','Audio','IFrame']);
 const errors:string[]=[];
 const visit=(n:ts.Node)=>{
  if(ts.isImportDeclaration(n)&&(!ts.isStringLiteral(n.moduleSpecifier)||!['react','remotion'].includes(n.moduleSpecifier.text)))errors.push('只允许导入 react 和 remotion');
  if(ts.isExportDeclaration(n)&&n.moduleSpecifier)errors.push('禁止重新导出外部模块');
  if(ts.isCallExpression(n)&&n.expression.kind===ts.SyntaxKind.ImportKeyword)errors.push('不允许动态导入');
  if(ts.isIdentifier(n)&&banned.has(n.text))errors.push(`不允许 ${n.text}`);
  if(ts.isStringLiteral(n)&&(/^(https?:|file:|data:|javascript:)/i.test(n.text)||['constructor','__proto__','prototype'].includes(n.text)))errors.push('不允许外部或嵌入资源');
  if(ts.isJsxAttribute(n)&&n.name.getText()==='dangerouslySetInnerHTML')errors.push('不允许直接注入 HTML');
  if(ts.isPropertyAccessExpression(n)&&['constructor','__proto__','prototype'].includes(n.name.text))errors.push('不允许动态执行');
  if(ts.isJsxOpeningElement(n)||ts.isJsxSelfClosingElement(n)){if(['video','audio','iframe','script','object','embed','link'].includes(n.tagName.getText()))errors.push('不允许嵌入原视频或外部页面');}
  ts.forEachChild(n,visit);
 };visit(tree);
 if(!/export\s+(?:const|function)\s+Scene\b/.test(code))errors.push('必须命名导出 Scene');
 if(errors.length)throw new Error([...new Set(errors)].join('；'));
}
export async function writeProject(project:string,code:string,props:Record<string,unknown>,fields:Field[],dimensions:{width:number;height:number;fps:number},runtimeRoot:string){
 validateScene(code);await fs.mkdir(path.join(project,'src'),{recursive:true});await fs.mkdir(path.join(project,'public','media'),{recursive:true});
 await fs.writeFile(path.join(project,'src','Scene.tsx'),code);
 const root=`import React from 'react';\nimport {Composition,registerRoot} from 'remotion';\nimport {Scene} from './Scene';\nimport defaults from '../props.json';\nconst Root=()=> <Composition id="Replica" component={Scene as any} width={${dimensions.width}} height={${dimensions.height}} fps={${dimensions.fps}} durationInFrames={Math.max(1,Math.round(Number(defaults.durationSeconds)*${dimensions.fps}))} defaultProps={defaults} calculateMetadata={({props})=>({durationInFrames:Math.max(1,Math.round(Number(props.durationSeconds)*${dimensions.fps}))})}/>;\nregisterRoot(Root);\n`;
 await fs.writeFile(path.join(project,'src','index.tsx'),root);await fs.writeFile(path.join(project,'props.json'),JSON.stringify(props,null,2));await fs.writeFile(path.join(project,'fields.json'),JSON.stringify(fields,null,2));
 await fs.writeFile(path.join(project,'package.json'),JSON.stringify({name:'editable-motion',version:'1.0.0',private:true,scripts:{dev:'remotion studio src/index.tsx',render:'remotion render src/index.tsx Replica out.mp4 --codec=h264',check:'tsc --noEmit'},dependencies:{react:'19.2.3','react-dom':'19.2.3',remotion:'4.0.533','@remotion/cli':'4.0.533'},devDependencies:{typescript:'5.9.3','@types/react':'19.2.7'}},null,2));
 await fs.writeFile(path.join(project,'tsconfig.json'),JSON.stringify({compilerOptions:{target:'ES2022',module:'ESNext',moduleResolution:'Bundler',jsx:'react-jsx',esModuleInterop:true,resolveJsonModule:true,skipLibCheck:true,noEmit:true,strict:false},include:['src','props.json']},null,2));
 const link=path.join(project,'node_modules');await fs.rm(link,{recursive:true,force:true});await fs.symlink(path.join(runtimeRoot,'node_modules'),link,'dir');
 await fs.writeFile(path.join(project,'README.md'),'# 可编辑动效\n\n修改 props.json 中的内容；图片替换到 public/media。\n\n```sh\nnpm install\nnpm run dev\nnpm run render\n```\n\n原片只作对照，不包含在本工程里。素材使用范围请以来源说明为准。\n');
}
