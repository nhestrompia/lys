import { readFile } from 'node:fs/promises';
import path from 'node:path';

export const dynamic = 'force-static';

export async function GET() {
  const skillPath = path.resolve(process.cwd(), '../../Skills/lys-integrate/SKILL.md');
  const skill = await readFile(skillPath, 'utf8');

  return new Response(skill, {
    headers: {
      'Content-Disposition': 'inline; filename="SKILL.md"',
      'Content-Type': 'text/markdown; charset=utf-8',
    },
  });
}
