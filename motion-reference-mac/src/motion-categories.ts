import {categories,type Category,type Job,type SegmentCategories} from './types';

export function isCategory(value:unknown):value is Category {
 return (categories as readonly unknown[]).includes(value);
}

export function normalizeCategories(values:unknown):Category[] {
 return Array.isArray(values)?[...new Set(values.filter(isCategory))]:[];
}

export function segmentCategories(segment?:SegmentCategories):Category[] {
 return normalizeCategories(segment?.categories??[segment?.category]);
}

export function detectedCategories(job:Job):Category[] {
 return normalizeCategories([
  ...(job.overviewCategories??[]),
  ...job.candidates.flatMap(segmentCategories),
  ...segmentCategories(job.brief),
  ...segmentCategories(job.analysis),
 ]);
}

export function jobCategories(job:Job):Category[] {
 return normalizeCategories([job.classification?.primary,...(job.classification?.secondary??[]),...detectedCategories(job)]);
}
