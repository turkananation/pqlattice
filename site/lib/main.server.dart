/// Static Jaspr documentation and measurements site for pqlattice.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:jaspr_content/components/callout.dart';
import 'package:jaspr_content/components/image.dart';
import 'package:jaspr_content/components/sidebar.dart';
import 'package:jaspr_content/jaspr_content.dart';
import 'package:jaspr_content/theme.dart';

import 'components/site_header.dart';
import 'main.server.options.dart';

void main() {
  Jaspr.initializeApp(options: defaultServerOptions);

  runApp(
    ContentApp(
      eagerlyLoadAllPages: true,
      templateEngine: MustacheTemplateEngine(),
      parsers: [MarkdownParser()],
      extensions: [HeadingAnchorsExtension(), TableOfContentsExtension()],
      components: [Callout(), Image(zoom: true)],
      layouts: [
        DocsLayout(
          header: const SiteHeader(),
          sidebar: const Sidebar(
            groups: [
              SidebarGroup(
                links: [SidebarLink(text: 'Overview', href: './')],
              ),
              SidebarGroup(
                title: 'Mathematics',
                links: [SidebarLink(text: 'Math from A to Z', href: 'math')],
              ),
              SidebarGroup(
                title: 'Measurements',
                links: [
                  SidebarLink(
                    text: 'Benchmarks & Stages',
                    href: 'measurements',
                  ),
                ],
              ),
              SidebarGroup(
                title: 'Project',
                links: [
                  SidebarLink(text: 'Getting Started', href: 'getting-started'),
                  SidebarLink(text: 'Architecture', href: 'architecture'),
                  SidebarLink(text: 'Security Posture', href: 'security'),
                  SidebarLink(text: 'Roadmap', href: 'roadmap'),
                ],
              ),
            ],
          ),
          footer: footer(classes: 'site-footer', [
            p([
              Component.text('pqlattice — pure-Dart lattice arithmetic. '),
              a(
                href: 'https://github.com/turkananation/pqlattice',
                target: Target.blank,
                [Component.text('GitHub')],
              ),
              Component.text(' · MIT license · evidence over claims.'),
            ]),
          ]),
        ),
      ],
      theme: ContentTheme(
        primary: ThemeColor(
          ThemeColors.indigo.$700,
          dark: ThemeColors.indigo.$300,
        ),
        background: ThemeColor(Color('#fbfaff'), dark: ThemeColors.zinc.$950),
        text: ThemeColor(ThemeColors.zinc.$700, dark: ThemeColors.zinc.$200),
        colors: [
          ContentColors.links.apply(
            ThemeColor(ThemeColors.indigo.$700, dark: ThemeColors.indigo.$300),
          ),
          ContentColors.quoteBorders.apply(
            ThemeColor(ThemeColors.rose.$400, dark: ThemeColors.rose.$300),
          ),
          ContentColors.preBg.apply(
            ThemeColor(Color('#111827'), dark: Color('#020617')),
          ),
        ],
      ),
    ),
  );
}
