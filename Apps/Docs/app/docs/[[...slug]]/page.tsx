import { getMDXComponents } from '@/components/mdx';
import { source } from '@/lib/source';
import {
  DocsBody,
  DocsDescription,
  DocsPage,
  DocsTitle,
  ViewOptionsPopover,
} from 'fumadocs-ui/layouts/docs/page';
import type { Metadata } from 'next';
import { notFound } from 'next/navigation';

type PageProps = {
  params: Promise<{ slug?: string[] }>;
};

export default async function Page({ params }: PageProps) {
  const { slug } = await params;
  const page = source.getPage(slug);
  if (!page) notFound();

  const MDX = page.data.body;
  const githubUrl = `https://github.com/nhestrompia/lys/blob/main/Apps/Docs/content/docs/${page.path}`;

  return (
    <DocsPage
      toc={page.data.toc}
      tableOfContent={{ style: 'clerk' }}
      full={page.slugs.length === 0}
    >
      <DocsTitle>{page.data.title}</DocsTitle>
      <DocsDescription>{page.data.description}</DocsDescription>
      <div className="lys-page-actions">
        <ViewOptionsPopover githubUrl={githubUrl} markdownUrl={`${page.url}.mdx`} />
      </div>
      <DocsBody>
        <MDX components={getMDXComponents()} />
      </DocsBody>
    </DocsPage>
  );
}

export async function generateStaticParams() {
  return source.generateParams();
}

export async function generateMetadata({ params }: PageProps): Promise<Metadata> {
  const { slug } = await params;
  const page = source.getPage(slug);
  if (!page) notFound();

  return {
    title: page.data.title,
    description: page.data.description,
  };
}
