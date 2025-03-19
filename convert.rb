
VERSION = '0.1.0'

class WaterlensHtmlConverter < Asciidoctor::Converter::Base
  register_for 'w-html'
  
  (QUOTE_TAGS = {
    monospaced: ['<code>', '</code>', true],
    emphasis: ['<em>', '</em>', true],
    strong: ['<strong>', '</strong>', true],
    double: ['&#8220;', '&#8221;'],
    single: ['&#8216;', '&#8217;'],
    mark: ['<mark>', '</mark>', true],
    superscript: ['<sup>', '</sup>', true],
    subscript: ['<sub>', '</sub>', true],
    asciimath: ['\$', '\$'],
    latexmath: ['\(', '\)'],
    # Opal can't resolve these constants when referenced here
    #asciimath: INLINE_MATH_DELIMITERS[:asciimath] + [false],
    #latexmath: INLINE_MATH_DELIMITERS[:latexmath] + [false],
  }).default = ['', '']
  DropAnchorRx = %r(<(?:a\b[^>]*|/a)>)
  StemBreakRx = / *\\\n(?:\\?\n)*|\n\n+/
  if RUBY_ENGINE == 'opal'
    # NOTE In JavaScript, ^ matches the start of the string when the m flag is not set
    SvgPreambleRx = /^#{CC_ALL}*?(?=<svg[\s>])/
    SvgStartTagRx = /^<svg(?:\s[^>]*)?>/
  else
    SvgPreambleRx = /\A.*?(?=<svg[\s>])/m
    SvgStartTagRx = /\A<svg(?:\s[^>]*)?>/
  end
  DimensionAttributeRx = /\s(?:width|height|style)=(["'])#{Asciidoctor::CC_ANY}*?\1/

  def initialize backend, opts = {}
    @backend = backend
    init_backend_traits filetype: 'w-html', outfilesuffix: '.html', supports_templates: true
  end
  
  def convert_document node
    br = %(<br>)

    unless (asset_uri_scheme = (node.attr 'asset-uri-scheme', 'https')).empty?
      asset_uri_scheme = %(#{asset_uri_scheme}:)
    end
    cdn_base_url = %(#{asset_uri_scheme}//cdnjs.cloudflare.com/ajax/libs)
    linkcss = node.attr? 'linkcss'
    max_width_attr = (node.attr? 'max-width') ? %( style="max-width: #{node.attr 'max-width'};") : ''
    lang_attribute = (node.attr? 'nolang') ? '' : %( lang="#{node.attr 'lang', 'en'}")
    result = []
    result << <<~EOS.chomp
      <!DOCTYPE html>
      <html#{lang_attribute}>
      <head>
      <meta charset="utf-8">
      <link rel="preconnect" href="https://fonts.googleapis.com">
      <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin="">
      <link href="https://fonts.googleapis.com/css2?family=Oxygen:wght@400;700&amp;display=swap" rel="stylesheet">
      <link href="https://fonts.googleapis.com/css2?family=Noto+Serif+SC:wght@400;700&amp;display=swap" rel="stylesheet">
      <link href="https://fonts.googleapis.com/css2?family=Noto+Sans+SC:wght@400;700&amp;display=swap" rel="stylesheet">
      <link href="https://cdn.jsdelivr.net/npm/hack-font@3/build/web/hack.css" rel="stylesheet">
      <link rel="stylesheet" href="/style.css">
    EOS
    if node.attr? 'stem'
      result << <<~EOS.chomp
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css" integrity="sha384-nB0miv6/jRmo5UMMR1wu3Gz6NLsoTkbqJghGIsx//Rlm+ZU03BU6SQNC66uf4l5+" crossorigin="anonymous">
        <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js" integrity="sha384-7zkQWkzuo3B5mTepMUcHkMB5jZaolc2xDwL6VFqjFALcbeS9Ggm/Yr2r3Dy4lfFg" crossorigin="anonymous"></script>
        <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/contrib/auto-render.min.js" integrity="sha384-43gviWU0YVjaDtb/GhzOouOXtZMP/7XUzwPTstBeZFe/+rCMvRwr4yROQP43s0Xk" crossorigin="anonymous" onload="renderMathInElement(document.body);"></script>
        <script src="https://cdn.jsdelivr.net/npm/mermaid@11.0.2/dist/mermaid.min.js" onload="mermaid.initialize({ startOnLoad: true });"></script>
      EOS
    end
    result << <<~EOS.chomp
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="generator" content="Asciidoctor #{Asciidoctor::VERSION} with Waterlens HTML Backend #{VERSION}">
      EOS
    # generate meta tags
    result << %(<meta name="description" content="#{node.attr 'description'}">) if node.attr? 'description'
    result << %(<meta name="keywords" content="#{node.attr 'keywords'}">) if node.attr? 'keywords'
    result << %(<meta name="author" content="#{node.attr 'author'}">) if node.attr? 'author'
    if node.attr? 'favicon'
      if (icon_href = node.attr 'favicon').empty?
        icon_href = 'favicon.ico'
        icon_type = 'image/x-icon'
      elsif (icon_ext = Helpers.extname icon_href, nil)
        icon_type = icon_ext == '.ico' ? 'image/x-icon' : %(image/#{icon_ext.slice 1, icon_ext.length})
      else
        icon_type = 'image/x-icon'
      end
      result << %(<link rel="icon" type="#{icon_type}" href="#{icon_href}">)
    end
    if node.attr? 'pagetitle'
      result << %(<title>#{node.attr 'pagetitle'}</title>)
    else
      result << %(<title>#{node.doctitle sanitize: true, use_fallback: true}</title>)
    end

    if Asciidoctor::DEFAULT_STYLESHEET_KEYS.include?(node.attr 'stylesheet')
      webfonts = node.attr 'webfonts'
      if !webfonts.empty?
        result << %(<link rel="stylesheet" href="#{asset_uri_scheme}//fonts.googleapis.com/css?family=#{webfonts}">)
      end
    elsif node.attr? 'stylesheet'
      if linkcss
        result << %(<link rel="stylesheet" href="#{node.normalize_web_path((node.attr 'stylesheet'), (node.attr 'stylesdir', ''))}"#{slash}>)
      else
        result << %(<style>
#{node.read_contents (node.attr 'stylesheet'), start: (node.attr 'stylesdir'), warn_on_failure: true, label: 'stylesheet'}
</style>)
      end
    end

    if node.attr? 'icons', 'font'
      if node.attr? 'iconfont-remote'
        result << %(<link rel="stylesheet" href="#{node.attr 'iconfont-cdn', %[#{cdn_base_url}/font-awesome/#{FONT_AWESOME_VERSION}/css/font-awesome.min.css]}"#{slash}>)
      else
        iconfont_stylesheet = %(#{node.attr 'iconfont-name', 'font-awesome'}.css)
        result << %(<link rel="stylesheet" href="#{node.normalize_web_path iconfont_stylesheet, (node.attr 'stylesdir', ''), false}"#{slash}>)
      end
    end

    if (syntax_hl = node.syntax_highlighter)
      result << (syntax_hl_docinfo_head_idx = result.size)
    end

    unless (docinfo_content = node.docinfo).empty?
      result << docinfo_content
    end

    result << '</head>'
    id_attr = node.id ? %( id="#{node.id}") : ''
    classes = []
    classes << node.role if node.role?
    result << %(<body#{id_attr}>)
    
    result << %(<article>) if !node.attr? 'shownav'

    unless (docinfo_content = node.docinfo :header).empty?
      result << docinfo_content
    end

    unless node.noheader
      result << %(<header>)
      doct = node.doctitle use_fallback: true, partition: ':'
      result << %(<h1>#{doct.main}</h1>) unless node.notitle
      result << %(<h2 class="subtitle">#{doct.subtitle}</h2>) if doct.subtitle?
      details = []
      idx = 1
      node.authors.each do |author|
        details << %(<span id="author#{idx > 1 ? idx : ''}" class="author">#{node.sub_replacements author.name}</span>#{br})
        details << %(<span id="email#{idx > 1 ? idx : ''}" class="email">#{node.sub_macros author.email}</span>#{br}) if author.email
        idx += 1
      end
      if node.attr? 'shownav'
        case node.attr 'lang'
        when 'zh-hans'
          result << <<~EOS.chomp
            <nav>
              <a href="/zh/index.html">主页</a>
              <a href="/zh/posts.html">文章</a>
              <a href="/zh/about.html">关于</a>
              <a href="/index.html">English</a>
              <a href="https://github.com/waterlens">Github</a>
            </nav>
          EOS
        else
          result << <<~EOS.chomp
            <nav>
              <a href="/index.html">Home</a>
              <a href="/posts.html">Posts</a>
              <a href="/about.html">About</a>
              <a href="/zh/index.html">中文</a>
              <a href="https://github.com/waterlens">Github</a>
            </nav>
          EOS
        end
      end
      result << %(</header>)
    end
    result << %(<hr>)

    result << %(<div id="content"#{max_width_attr}>
#{node.content}
</div>)
    result << '<hr>'

    if node.footnotes? && !(node.attr? 'nofootnotes')
      result << %(<div id="footnotes"#{max_width_attr}>)
      node.footnotes.each do |footnote|
        result << %(<div class="footnote" id="_footnotedef_#{footnote.index}">
<a href="#_footnoteref_#{footnote.index}">#{footnote.index}</a>. #{footnote.text}
</div>)
      end
      result << '</div>'
    end

    unless node.nofooter 
      case node.attr 'lang'
      when 'zh-hans'
        result << <<~EOS.chomp
        <footer>
          <p>
            <a property="dct:title" rel="cc:attributionURL" href="/zh/index.html">本站</a>
            由 <span property="cc:attributionName">Waterlens</span>
            创作的一切内容 © 2021 - #{Time.now.year} 在
            <a href="http://creativecommons.org/licenses/by-sa/4.0/?ref=chooser-v1" target="_blank" rel="license noopener noreferrer" style="display:inline-block;">
                知识共享 署名 - 相同方式共享 4.0 协议 <img alt="" style="height:22px!important;margin-left:3px;vertical-align:text-bottom;" src="https://mirrors.creativecommons.org/presskit/icons/cc.svg?ref=chooser-v1">
                <img alt="" style="height:22px!important;margin-left:3px;vertical-align:text-bottom;" src="https://mirrors.creativecommons.org/presskit/icons/by.svg?ref=chooser-v1">
                <img alt="" style="height:22px!important;margin-left:3px;vertical-align:text-bottom;" src="https://mirrors.creativecommons.org/presskit/icons/sa.svg?ref=chooser-v1">
            </a>
            之条款下提供。
          </p>
        </footer>
        EOS
      else
        result << <<~EOS.chomp
        <footer>
          <p>
            The content on <a property="dct:title" rel="cc:attributionURL" href="/">this website</a>
            © 2021 - 2024 by <span property="cc:attributionName">Waterlens</span>
            is licensed under 
            <a href="http://creativecommons.org/licenses/by-sa/4.0/?ref=chooser-v1" target="_blank" rel="license noopener noreferrer" style="display:inline-block;">
                CC BY-SA 4.0 <img alt="" style="height:22px!important;margin-left:3px;vertical-align:text-bottom;" src="https://mirrors.creativecommons.org/presskit/icons/cc.svg?ref=chooser-v1">
                <img alt="" style="height:22px!important;margin-left:3px;vertical-align:text-bottom;" src="https://mirrors.creativecommons.org/presskit/icons/by.svg?ref=chooser-v1">
                <img alt="" style="height:22px!important;margin-left:3px;vertical-align:text-bottom;" src="https://mirrors.creativecommons.org/presskit/icons/sa.svg?ref=chooser-v1">
            </a>
          </p>
        </footer>
        EOS
      end
    end

    if syntax_hl
      if syntax_hl.docinfo? :head
        result[syntax_hl_docinfo_head_idx] = syntax_hl.docinfo :head, node, cdn_base_url: cdn_base_url, linkcss: linkcss, self_closing_tag_slash: slash
      else
        result.delete_at syntax_hl_docinfo_head_idx
      end
      if syntax_hl.docinfo? :footer
        result << (syntax_hl.docinfo :footer, node, cdn_base_url: cdn_base_url, linkcss: linkcss, self_closing_tag_slash: slash)
      end
    end

    unless (docinfo_content = node.docinfo :footer).empty?
      result << docinfo_content
    end

    result << '</article>' if !node.attr? 'shownav'
    result << '</body>'
    result << '</html>'

    result.join Asciidoctor::LF
  end

  def convert_section node
    doc_attrs = node.document.attributes
    level = node.level
    if node.caption
      title = node.captioned_title
    elsif node.numbered && level <= (doc_attrs['sectnumlevels'] || 3).to_i
      title = %(#{node.sectnum} #{node.title})
    else
      title = node.title
    end
    if node.id
      id_attr = %( id="#{id = node.id}")
      if doc_attrs['sectlinks']
        title = %(<a class="link" href="##{id}">#{title}</a>)
      end
      if doc_attrs['sectanchors']
        if doc_attrs['sectanchors'] == 'after'
          title = %(#{title}<a class="anchor" href="##{id}"></a>)
        else
          title = %(<a class="anchor" href="##{id}"></a>#{title})
        end
      end
    else
      id_attr = ''
    end
    if level == 0
      %(<h1#{id_attr} class="sect0#{(role = node.role) ? " #{role}" : ''}">#{title}</h1>
#{node.content})
    else
      <<~EOS.chomp
      <section class="sect#{level}#{(role = node.role) ? " #{role}" : ''}">
      <h#{level + 1}#{id_attr}>#{title}</h#{level + 1}>
      #{node.content}
      </section>
      EOS
    end
  end

  def convert_admonition node
    id_attr = node.id ? %( id="#{node.id}") : ''
    name = node.attr 'name'
    title_element = node.title? ? %(<div class="title">#{node.title}</div>\n) : ''
    if node.document.attr? 'icons'
      if (node.document.attr? 'icons', 'font') && !(node.attr? 'icon')
        label = %(<i class="fa icon-#{name}" title="#{node.attr 'textlabel'}"></i>)
      else
        label = %(<img src="#{node.icon_uri name}" alt="#{node.attr 'textlabel'}">)
      end
    else
      label = %(<div class="title">#{node.attr 'textlabel'}</div>)
    end
    %(<div#{id_attr} class="admonition #{name}#{(role = node.role) ? " #{role}" : ''}">
<table>
<tr>
<td class="icon">
#{label}
</td>
<td class="content">
#{title_element}#{node.content}
</td>
</tr>
</table>
</div>)
  end

  def convert_audio node
    xml = @xml_mode
    id_attribute = node.id ? %( id="#{node.id}") : ''
    classes = ['audio', node.role].compact
    class_attribute = %( class="#{classes.join ' '}")
    title_element = node.title? ? %(<div class="title">#{node.title}</div>\n) : ''
    start_t = node.attr 'start'
    end_t = node.attr 'end'
    time_anchor = (start_t || end_t) ? %(#t=#{start_t || ''}#{end_t ? ",#{end_t}" : ''}) : ''
    %(<div#{id_attribute}#{class_attribute}>
#{title_element}<div class="content">
<audio src="#{node.media_uri(node.attr 'target')}#{time_anchor}"#{(node.option? 'autoplay') ? (append_boolean_attribute 'autoplay', xml) : ''}#{(node.option? 'nocontrols') ? '' : (append_boolean_attribute 'controls', xml)}#{(node.option? 'loop') ? (append_boolean_attribute 'loop', xml) : ''}>
Your browser does not support the audio tag.
</audio>
</div>
</div>)
  end


  def convert_colist node
    result = []
    id_attribute = node.id ? %( id="#{node.id}") : ''
    classes = ['colist', node.style, node.role].compact
    class_attribute = %( class="#{classes.join ' '}")

    result << %(<div#{id_attribute}#{class_attribute}>)
    result << %(<div class="title">#{node.title}</div>) if node.title?

    if node.document.attr? 'icons'
      result << '<table>'
      font_icons, num = (node.document.attr? 'icons', 'font'), 0
      node.items.each do |item|
        num += 1
        if font_icons
          num_label = %(<i class="conum" data-value="#{num}"></i><b>#{num}</b>)
        else
          num_label = %(<img src="#{node.icon_uri "callouts/#{num}"}" alt="#{num}">)
        end
        result << %(<tr>
<td>#{num_label}</td>
<td>#{item.text}#{item.blocks? ? LF + item.content : ''}</td>
</tr>)
      end
      result << '</table>'
    else
      result << '<ol>'
      node.items.each do |item|
        result << %(<li>
<p>#{item.text}</p>#{item.blocks? ? LF + item.content : ''}
</li>)
      end
      result << '</ol>'
    end

    result << '</div>'
    result.join Asciidoctor::LF
  end

  def convert_dlist node
    result = []
    id_attribute = node.id ? %( id="#{node.id}") : ''

    case node.style
    when 'qanda'
      classes = ['qlist', 'qanda', node.role]
    when 'horizontal'
      classes = ['hdlist', node.role]
    else
      classes = ['dlist', node.style, node.role]
    end

    class_attribute = %( class="#{classes.compact.join ' '}")

    result << %(<div#{id_attribute}#{class_attribute}>)
    result << %(<div class="title">#{node.title}</div>) if node.title?
    case node.style
    when 'qanda'
      result << '<ol>'
      node.items.each do |terms, dd|
        result << '<li>'
        terms.each do |dt|
          result << %(<p><em>#{dt.text}</em></p>)
        end
        if dd
          result << %(<p>#{dd.text}</p>) if dd.text?
          result << dd.content if dd.blocks?
        end
        result << '</li>'
      end
      result << '</ol>'
    when 'horizontal'
      result << '<table>'
      if (node.attr? 'labelwidth') || (node.attr? 'itemwidth')
        result << '<colgroup>'
        col_style_attribute = (node.attr? 'labelwidth') ? %( style="width: #{(node.attr 'labelwidth').chomp '%'}%;") : ''
        result << %(<col#{col_style_attribute}>)
        col_style_attribute = (node.attr? 'itemwidth') ? %( style="width: #{(node.attr 'itemwidth').chomp '%'}%;") : ''
        result << %(<col#{col_style_attribute}>)
        result << '</colgroup>'
      end
      node.items.each do |terms, dd|
        result << '<tr>'
        result << %(<td class="hdlist1#{(node.option? 'strong') ? ' strong' : ''}">)
        first_term = true
        terms.each do |dt|
          result << %(<br>) unless first_term
          result << dt.text
          first_term = nil
        end
        result << '</td>'
        result << '<td class="hdlist2">'
        if dd
          result << %(<p>#{dd.text}</p>) if dd.text?
          result << dd.content if dd.blocks?
        end
        result << '</td>'
        result << '</tr>'
      end
      result << '</table>'
    else
      result << '<dl>'
      dt_style_attribute = node.style ? '' : ' class="hdlist1"'
      node.items.each do |terms, dd|
        terms.each do |dt|
          result << %(<dt#{dt_style_attribute}>#{dt.text}</dt>)
        end
        next unless dd
        result << '<dd>'
        result << %(<p>#{dd.text}</p>) if dd.text?
        result << dd.content if dd.blocks?
        result << '</dd>'
      end
      result << '</dl>'
    end

    result << '</div>'
    result.join Asciidoctor::LF
  end

  def convert_example node
    id_attribute = node.id ? %( id="#{node.id}") : ''
    if node.option? 'collapsible'
      class_attribute = node.role ? %( class="#{node.role}") : ''
      summary_element = node.title? ? %(<summary class="title">#{node.title}</summary>) : '<summary class="title">Details</summary>'
      %(<details#{id_attribute}#{class_attribute}#{(node.option? 'open') ? ' open' : ''}>
#{summary_element}
<div class="content">
#{node.content}
</div>
</details>)
    else
      title_element = node.title? ? %(<div class="title">#{node.captioned_title}</div>\n) : ''
      %(<div#{id_attribute} class="example#{(role = node.role) ? " #{role}" : ''}">
#{title_element}<div class="content">
#{node.content}
</div>
</div>)
    end
  end

  def convert_embedded node
    result = []
    if node.header? && !node.notitle
      id_attr = node.id ? %( id="#{node.id}") : ''
      result << %(<h1#{id_attr}>#{node.header.title}</h1>)
    end

    result << node.content
    result.join Asciidoctor::LF
  end

  def convert_floating_title node
    tag_name = %(h#{node.level + 1})
    id_attribute = node.id ? %( id="#{node.id}") : ''
    classes = [node.style, node.role].compact
    %(<#{tag_name}#{id_attribute} class="#{classes.join ' '}">#{node.title}</#{tag_name}>)
  end

  def convert_image node
    target = node.attr 'target'
    width_attr = ''
    if (node.attr? 'width')
      if ((node.attr 'width').end_with? 'rem')
        width_attr = %( style="width: #{node.attr 'width'};")
      else
        width_attr = %( width="#{node.attr 'width'}")
      end
    end
    if (node.attr? 'height')
      if ((node.attr 'height').end_with? 'rem')
        height_attr = %( style="height: #{node.attr 'height'};")
      else
        height_attr = %( height="#{node.attr 'height'}")
      end
    end
    if ((node.attr? 'format', 'svg') || (target.include? '.svg'))
      if node.option? 'inline'
        img = (read_svg_contents node, target) || %(<span class="alt">#{node.alt}</span>)
      elsif node.option? 'interactive'
        fallback = (node.attr? 'fallback') ? %(<img src="#{node.image_uri node.attr 'fallback'}" alt="#{encode_attribute_value node.alt}"#{width_attr}#{height_attr}>) : %(<span class="alt">#{node.alt}</span>)
        img = %(<object type="image/svg+xml" data="#{node.image_uri target}"#{width_attr}#{height_attr}>#{fallback}</object>)
      else
        img = %(<img src="#{node.image_uri target}" alt="#{encode_attribute_value node.alt}"#{width_attr}#{height_attr}>)
      end
    else
      img = %(<img src="#{node.image_uri target}" alt="#{encode_attribute_value node.alt}"#{width_attr}#{height_attr}>)
    end
    img = %(<a class="image" href="#{node.attr 'link'}"#{(append_link_constraint_attrs node).join}>#{img}</a>) if node.attr? 'link'
    id_attr = node.id ? %( id="#{node.id}") : ''
    classes = ['imageblock']
    classes << (node.attr 'float') if node.attr? 'float'
    classes << %(text-#{node.attr 'align'}) if node.attr? 'align'
    classes << node.role if node.role
    class_attr = %( class="#{classes.join ' '}")
    title_el = node.title? ? %(\n<div class="title">#{node.captioned_title}</div>) : ''
    %(<div#{id_attr}#{class_attr}>
<div class="content">
#{img}
</div>#{title_el}
</div>)
  end

  def convert_listing node
    nowrap = (node.option? 'nowrap') || !(node.document.attr? 'prewrap')
    if node.style == 'source'
      lang = node.attr 'language'
      if (syntax_hl = node.document.syntax_highlighter)
        opts = syntax_hl.highlight? ? {
          css_mode: ((doc_attrs = node.document.attributes)[%(#{syntax_hl.name}-css)] || :class).to_sym,
          style: doc_attrs[%(#{syntax_hl.name}-style)],
        } : {}
        opts[:nowrap] = nowrap
      else
        pre_open = %(<pre class="highlight#{nowrap ? ' nowrap' : ''}"><code#{lang ? %[ class="language-#{lang}" data-lang="#{lang}"] : ''}>)
        pre_close = '</code></pre>'
      end
    else
      pre_open = %(<pre#{nowrap ? ' class="nowrap"' : ''}>)
      pre_close = '</pre>'
    end
    id_attribute = node.id ? %( id="#{node.id}") : ''
    title_element = node.title? ? %(<div class="title">#{node.captioned_title}</div>\n) : ''
    %(<div#{id_attribute} class="listing#{(role = node.role) ? " #{role}" : ''}">
#{title_element}<div class="content">
#{syntax_hl ? (syntax_hl.format node, lang, opts) : pre_open + node.content + pre_close}
</div>
</div>)
  end

  def convert_literal node
    id_attribute = node.id ? %( id="#{node.id}") : ''
    title_element = node.title? ? %(<div class="title">#{node.title}</div>\n) : ''
    nowrap = !(node.document.attr? 'prewrap') || (node.option? 'nowrap')
    %(<div#{id_attribute} class="literal#{(role = node.role) ? " #{role}" : ''}">
#{title_element}<div class="content">
<pre#{nowrap ? ' class="nowrap"' : ''}>#{node.content}</pre>
</div>
</div>)
  end

  def convert_stem node
    id_attribute = node.id ? %( id="#{node.id}") : ''
    title_element = node.title? ? %(<div class="title">#{node.title}</div>\n) : ''
    open, close = Asciidoctor::BLOCK_MATH_DELIMITERS[style = node.style.to_sym]
    if (equation = node.content)
      if style == :asciimath && (equation.include? LF)
        br = %(#{LF}<br>)
        equation = equation.gsub(StemBreakRx) { %(#{close}#{br * (($&.count LF) - 1)}#{LF}#{open}) }
      end
      unless (equation.start_with? open) && (equation.end_with? close)
        equation = %(#{open}#{equation}#{close})
      end
    else
      equation = ''
    end
    %(<div#{id_attribute} class="stem#{(role = node.role) ? " #{role}" : ''}">
#{title_element}<div class="content">
#{equation}
</div>
</div>)
  end


  def convert_olist node
    result = []
    id_attribute = node.id ? %( id="#{node.id}") : ''
    classes = ['olist', node.style, node.role].compact
    class_attribute = %( class="#{classes.join ' '}")

    result << %(<div#{id_attribute}#{class_attribute}>)
    result << %(<div class="title">#{node.title}</div>) if node.title?

    type_attribute = (keyword = node.list_marker_keyword) ? %( type="#{keyword}") : ''
    start_attribute = (node.attr? 'start') ? %( start="#{node.attr 'start'}") : ''
    reversed_attribute = (node.option? 'reversed') ? (append_boolean_attribute 'reversed', @xml_mode) : ''
    result << %(<ol class="#{node.style}"#{type_attribute}#{start_attribute}#{reversed_attribute}>)

    node.items.each do |item|
      if item.id
        result << %(<li id="#{item.id}"#{item.role ? %[ class="#{item.role}"] : ''}>)
      elsif item.role
        result << %(<li class="#{item.role}">)
      else
        result << '<li>'
      end
      result << %(<p>#{item.text}</p>)
      result << item.content if item.blocks?
      result << '</li>'
    end

    result << '</ol>'
    result << '</div>'
    result.join Asciidoctor::LF
  end

  def convert_open node
    if (style = node.style) == 'abstract'
      if node.parent == node.document && node.document.doctype == 'book'
        logger.warn 'abstract block cannot be used in a document without a doctitle when doctype is book. Excluding block content.'
        ''
      else
        id_attr = node.id ? %( id="#{node.id}") : ''
        title_el = node.title? ? %(<div class="title">#{node.title}</div>\n) : ''
        %(<div#{id_attr} class="quote abstract#{(role = node.role) ? " #{role}" : ''}">
#{title_el}<blockquote>
#{node.content}
</blockquote>
</div>)
      end
    elsif style == 'partintro' && (node.level > 0 || node.parent.context != :section || node.document.doctype != 'book')
      logger.error 'partintro block can only be used when doctype is book and must be a child of a book part. Excluding block content.'
      ''
    else
      id_attr = node.id ? %( id="#{node.id}") : ''
      title_el = node.title? ? %(<div class="title">#{node.title}</div>\n) : ''
      %(<div#{id_attr} class="open#{style && style != 'open' ? " #{style}" : ''}#{(role = node.role) ? " #{role}" : ''}">
#{title_el}<div class="content">
#{node.content}
</div>
</div>)
    end
  end

  def convert_page_break node
    '<div style="page-break-after: always;"></div>'
  end

  def convert_paragraph node
    if node.title?
      if node.role
        attributes = %(#{node.id ? %[ id="#{node.id}"] : ''} class="paragraph #{node.role}")
      elsif node.id
        attributes = %( id="#{node.id}" class="paragraph")
      else
        attributes = ' class="paragraph"'
      end
      %(<div#{attributes}>
<div class="title">#{node.title}</div>
<p>#{node.content}</p>
</div>)
    else
      if node.role
        attributes = %(#{node.id ? %[ id="#{node.id}"] : ''} class="paragraph #{node.role}")
      elsif node.id
        attributes = %( id="#{node.id}")
      else
        attributes = ''
      end
      %(<p#{attributes}>#{node.content}</p>)
    end
  end

  alias convert_pass content_only

  def convert_preamble node
    node.content
  end

  def convert_quote node
    id_attribute = node.id ? %( id="#{node.id}") : ''
    classes = ['quoteblock', node.role].compact
    class_attribute = %( class="#{classes.join ' '}")
    title_element = node.title? ? %(\n<div class="title">#{node.title}</div>) : ''
    attribution = (node.attr? 'attribution') ? (node.attr 'attribution') : nil
    citetitle = (node.attr? 'citetitle') ? (node.attr 'citetitle') : nil
    if attribution || citetitle
      cite_element = citetitle ? %(<cite>#{citetitle}</cite>) : ''
      attribution_text = attribution ? %(&#8212; #{attribution}#{citetitle ? "<br>\n" : ''}) : ''
      attribution_element = %(\n<div class="attribution">\n#{attribution_text}#{cite_element}\n</div>)
    else
      attribution_element = ''
    end

    %(<div#{id_attribute}#{class_attribute}>#{title_element}
<blockquote>
#{node.content}
</blockquote>#{attribution_element}
</div>)
  end

  def convert_thematic_break node
    %(<hr>)
  end

  def convert_sidebar node
    id_attribute = node.id ? %( id="#{node.id}") : ''
    title_element = node.title? ? %(<div class="title">#{node.title}</div>\n) : ''
    %(<div#{id_attribute} class="sidebar#{(role = node.role) ? " #{role}" : ''}">
<div class="content">
#{title_element}#{node.content}
</div>
</div>)
  end

  def convert_table node
    result = []
    id_attribute = node.id ? %( id="#{node.id}") : ''
    frame = 'ends' if (frame = node.attr 'frame', 'all', 'table-frame') == 'topbot'
    classes = ['table', %(frame-#{frame}), %(grid-#{node.attr 'grid', 'all', 'table-grid'})]
    if (stripes = node.attr 'stripes', nil, 'table-stripes')
      classes << %(stripes-#{stripes})
    end
    style_attribute = ''
    if (autowidth = node.option? 'autowidth') && !(node.attr? 'width')
      classes << 'fit-content'
    elsif (tablewidth = node.attr 'tablepcwidth') == 100
      classes << 'stretch'
    else
      style_attribute = %( style="width: #{tablewidth}%;")
    end
    classes << (node.attr 'float') if node.attr? 'float'
    if (role = node.role)
      classes << role
    end
    class_attribute = %( class="#{classes.join ' '}")

    result << %(<table#{id_attribute}#{class_attribute}#{style_attribute}>)
    result << %(<caption class="title">#{node.captioned_title}</caption>) if node.title?
    if (node.attr 'rowcount') > 0
      result << '<colgroup>'
      if autowidth
        result += (Array.new node.columns.size, %(<col>))
      else
        node.columns.each do |col|
          result << ((col.option? 'autowidth') ? %(<col>) : %(<col style="width: #{col.attr 'colpcwidth'}%;">))
        end
      end
      result << '</colgroup>'
      node.rows.to_h.each do |tsec, rows|
        next if rows.empty?
        result << %(<t#{tsec}>)
        rows.each do |row|
          result << '<tr>'
          row.each do |cell|
            if tsec == :head
              cell_content = cell.text
            else
              case cell.style
              when :asciidoc
                cell_content = %(<div class="content">#{cell.content}</div>)
              when :literal
                cell_content = %(<div class="literal"><pre>#{cell.text}</pre></div>)
              else
                cell_content = (cell_content = cell.content).empty? ? '' : %(<p class="table">#{cell_content.join '</p>
<p class="table">'}</p>)
              end
            end

            cell_tag_name = (tsec == :head || cell.style == :header ? 'th' : 'td')
            cell_class_attribute = %( class="table halign-#{cell.attr 'halign'} valign-#{cell.attr 'valign'}")
            cell_colspan_attribute = cell.colspan ? %( colspan="#{cell.colspan}") : ''
            cell_rowspan_attribute = cell.rowspan ? %( rowspan="#{cell.rowspan}") : ''
            cell_style_attribute = (node.document.attr? 'cellbgcolor') ? %( style="background-color: #{node.document.attr 'cellbgcolor'};") : ''
            result << %(<#{cell_tag_name}#{cell_class_attribute}#{cell_colspan_attribute}#{cell_rowspan_attribute}#{cell_style_attribute}>#{cell_content}</#{cell_tag_name}>)
          end
          result << '</tr>'
        end
        result << %(</t#{tsec}>)
      end
    end
    result << '</table>'
    result.join Asciidoctor::LF
  end

  def convert_ulist node
    result = []
    id_attribute = node.id ? %( id="#{node.id}") : ''
    div_classes = ['ulist', node.style, node.role].compact
    marker_checked = marker_unchecked = ''
    if (checklist = node.option? 'checklist')
      div_classes.unshift div_classes.shift, 'checklist'
      ul_class_attribute = ' class="checklist"'
      if node.option? 'interactive'
        marker_checked = '<input type="checkbox" data-item-complete="1" checked> '
        marker_unchecked = '<input type="checkbox" data-item-complete="0"> '
      elsif node.document.attr? 'icons', 'font'
        marker_checked = '<i class="fa fa-check-square-o"></i> '
        marker_unchecked = '<i class="fa fa-square-o"></i> '
      else
        marker_checked = '&#10003; '
        marker_unchecked = '&#10063; '
      end
    else
      ul_class_attribute = node.style ? %( class="#{node.style}") : ''
    end
    result << %(<div#{id_attribute} class="#{div_classes.join ' '}">)
    result << %(<div class="title">#{node.title}</div>) if node.title?
    result << %(<ul#{ul_class_attribute}>)

    node.items.each do |item|
      if item.id
        result << %(<li id="#{item.id}"#{item.role ? %[ class="#{item.role}"] : ''}>)
      elsif item.role
        result << %(<li class="#{item.role}">)
      else
        result << '<li>'
      end
      if checklist && (item.attr? 'checkbox')
        result << %(<p>#{(item.attr? 'checked') ? marker_checked : marker_unchecked}#{item.text}</p>)
      else
        result << %(<p>#{item.text}</p>)
      end
      result << item.content if item.blocks?
      result << '</li>'
    end

    result << '</ul>'
    result << '</div>'
    result.join Asciidoctor::LF
  end

  def convert_verse node
    id_attribute = node.id ? %( id="#{node.id}") : ''
    classes = ['verse', node.role].compact
    class_attribute = %( class="#{classes.join ' '}")
    title_element = node.title? ? %(\n<div class="title">#{node.title}</div>) : ''
    attribution = (node.attr? 'attribution') ? (node.attr 'attribution') : nil
    citetitle = (node.attr? 'citetitle') ? (node.attr 'citetitle') : nil
    if attribution || citetitle
      cite_element = citetitle ? %(<cite>#{citetitle}</cite>) : ''
      attribution_text = attribution ? %(&#8212; #{attribution}#{citetitle ? "<br>\n" : ''}) : ''
      attribution_element = %(\n<div class="attribution">\n#{attribution_text}#{cite_element}\n</div>)
    else
      attribution_element = ''
    end

    %(<div#{id_attribute}#{class_attribute}>#{title_element}
<pre class="content">#{node.content}</pre>#{attribution_element}
</div>)
  end

  def convert_video node

  end

  def convert_inline_anchor node
    case node.type
    when :xref
      if (path = node.attributes['path'])
        attrs = (append_link_constraint_attrs node, node.role ? [%( class="#{node.role}")] : []).join
        text = node.text || path
      else
        attrs = node.role ? %( class="#{node.role}") : ''
        unless (text = node.text)
          if Asciidoctor::AbstractNode === (ref = (@refs ||= node.document.catalog[:refs])[refid = node.attributes['refid']] || (refid.nil_or_empty? ? (top = get_root_document node) : nil))
            if (@resolving_xref ||= (outer = true)) && outer
              if (text = ref.xreftext node.attr 'xrefstyle', nil, true)
                text = text.gsub DropAnchorRx, '' if text.include? '<a'
              else
                text = top ? '[^top]' : %([#{refid}])
              end
              @resolving_xref = nil
            else
              text = top ? '[^top]' : %([#{refid}])
            end
          else
            text = %([#{refid}])
          end
        end
      end
      %(<a href="#{node.target}"#{attrs}>#{text}</a>)
    when :ref
      %(<a id="#{node.id}"></a>)
    when :link
      attrs = node.id ? [%( id="#{node.id}")] : []
      attrs << %( class="#{node.role}") if node.role
      attrs << %( title="#{node.attr 'title'}") if node.attr? 'title'
      %(<a href="#{node.target}"#{(append_link_constraint_attrs node, attrs).join}>#{node.text}</a>)
    when :bibref
      %(<a id="#{node.id}"></a>[#{node.reftext || node.id}])
    else
      logger.warn %(unknown anchor type: #{node.type.inspect})
      nil
    end
  end

  def convert_inline_break node
    %(#{node.text}<br>)
  end

  def convert_inline_button node
    %(<b class="button">#{node.text}</b>)
  end

  def convert_inline_callout node
    if node.document.attr? 'icons', 'font'
      %(<i class="conum" data-value="#{node.text}"></i><b>(#{node.text})</b>)
    elsif node.document.attr? 'icons'
      src = node.icon_uri("callouts/#{node.text}")
      %(<img src="#{src}" alt="#{node.text}"#{@void_element_slash}>)
    elsif ::Array === (guard = node.attributes['guard'])
      %(&lt;!--<b class="conum">(#{node.text})</b>--&gt;)
    else
      %(#{guard}<b class="conum">(#{node.text})</b>)
    end
  end

  def convert_inline_footnote node
    if (index = node.attr 'index')
      if node.type == :xref
        %(<sup class="footnoteref">[<a class="footnote" href="#_footnotedef_#{index}" title="View footnote.">#{index}</a>]</sup>)
      else
        id_attr = node.id ? %( id="_footnote_#{node.id}") : ''
        %(<sup class="footnote"#{id_attr}>[<a id="_footnoteref_#{index}" class="footnote" href="#_footnotedef_#{index}" title="View footnote.">#{index}</a>]</sup>)
      end
    elsif node.type == :xref
      %(<sup class="footnoteref red" title="Unresolved footnote reference.">[#{node.text}]</sup>)
    end
  end

  def convert_inline_image node
    target = node.target
    if (type = node.type || 'image') == 'icon'
      if (icons = node.document.attr 'icons') == 'font'
        i_class_attr_val = %(fa fa-#{target})
        i_class_attr_val = %(#{i_class_attr_val} fa-#{node.attr 'size'}) if node.attr? 'size'
        if node.attr? 'flip'
          i_class_attr_val = %(#{i_class_attr_val} fa-flip-#{node.attr 'flip'})
        elsif node.attr? 'rotate'
          i_class_attr_val = %(#{i_class_attr_val} fa-rotate-#{node.attr 'rotate'})
        end
        attrs = (node.attr? 'title') ? %( title="#{node.attr 'title'}") : ''
        img = %(<i class="#{i_class_attr_val}"#{attrs}></i>)
      elsif icons
        attrs = (node.attr? 'width') ? %( width="#{node.attr 'width'}") : ''
        attrs = %(#{attrs} height="#{node.attr 'height'}") if node.attr? 'height'
        attrs = %(#{attrs} title="#{node.attr 'title'}") if node.attr? 'title'
        img = %(<img src="#{node.icon_uri target}" alt="#{encode_attribute_value node.alt}"#{attrs}#{@void_element_slash}>)
      else
        img = %([#{node.alt}&#93;)
      end
    else
      attrs = (node.attr? 'width') ? %( width="#{node.attr 'width'}") : ''
      attrs = %(#{attrs} height="#{node.attr 'height'}") if node.attr? 'height'
      attrs = %(#{attrs} title="#{node.attr 'title'}") if node.attr? 'title'
      if ((node.attr? 'format', 'svg') || (target.include? '.svg')) && node.document.safe < SafeMode::SECURE
        if node.option? 'inline'
          img = (read_svg_contents node, target) || %(<span class="alt">#{node.alt}</span>)
        elsif node.option? 'interactive'
          fallback = (node.attr? 'fallback') ? %(<img src="#{node.image_uri node.attr 'fallback'}" alt="#{encode_attribute_value node.alt}"#{attrs}#{@void_element_slash}>) : %(<span class="alt">#{node.alt}</span>)
          img = %(<object type="image/svg+xml" data="#{node.image_uri target}"#{attrs}>#{fallback}</object>)
        else
          img = %(<img src="#{node.image_uri target}" alt="#{encode_attribute_value node.alt}"#{attrs}#{@void_element_slash}>)
        end
      else
        img = %(<img src="#{node.image_uri target}" alt="#{encode_attribute_value node.alt}"#{attrs}#{@void_element_slash}>)
      end
    end
    img = %(<a class="image" href="#{node.attr 'link'}"#{(append_link_constraint_attrs node).join}>#{img}</a>) if node.attr? 'link'
    class_attr_val = type
    if (role = node.role)
      class_attr_val = (node.attr? 'float') ? %(#{class_attr_val} #{node.attr 'float'} #{role}) : %(#{class_attr_val} #{role})
    elsif node.attr? 'float'
      class_attr_val = %(#{class_attr_val} #{node.attr 'float'})
    end
    %(<span class="#{class_attr_val}">#{img}</span>)
  end

  def convert_inline_indexterm node
    node.type == :visible ? node.text : ''
  end

  def convert_inline_kbd node
    if (keys = node.attr 'keys').size == 1
      %(<kbd>#{keys[0]}</kbd>)
    else
      %(<span class="keyseq"><kbd>#{keys.join '</kbd>+<kbd>'}</kbd></span>)
    end
  end

  def convert_inline_menu node
    caret = (node.document.attr? 'icons', 'font') ? '&#160;<i class="fa fa-angle-right caret"></i> ' : '&#160;<b class="caret">&#8250;</b> '
    submenu_joiner = %(</b>#{caret}<b class="submenu">)
    menu = node.attr 'menu'
    if (submenus = node.attr 'submenus').empty?
      if (menuitem = node.attr 'menuitem')
        %(<span class="menuseq"><b class="menu">#{menu}</b>#{caret}<b class="menuitem">#{menuitem}</b></span>)
      else
        %(<b class="menuref">#{menu}</b>)
      end
    else
      %(<span class="menuseq"><b class="menu">#{menu}</b>#{caret}<b class="submenu">#{submenus.join submenu_joiner}</b>#{caret}<b class="menuitem">#{node.attr 'menuitem'}</b></span>)
    end
  end

  def convert_inline_quoted node
    open, close, tag = QUOTE_TAGS[node.type]
    if node.id
      class_attr = node.role ? %( class="#{node.role}") : ''
      if tag
        %(#{open.chop} id="#{node.id}"#{class_attr}>#{node.text}#{close})
      else
        %(<span id="#{node.id}"#{class_attr}>#{open}#{node.text}#{close}</span>)
      end
    elsif node.role
      if tag
        %(#{open.chop} class="#{node.role}">#{node.text}#{close})
      else
        %(<span class="#{node.role}">#{open}#{node.text}#{close}</span>)
      end
    else
      %(#{open}#{node.text}#{close})
    end
  end

  private

  def append_boolean_attribute name, xml
    xml ? %( #{name}="#{name}") : %( #{name})
  end

  def append_link_constraint_attrs node, attrs = []
    rel = 'nofollow' if node.option? 'nofollow'
    if (window = node.attributes['window'])
      attrs << %( target="#{window}")
      attrs << (rel ? %( rel="#{rel} noopener") : ' rel="noopener"') if window == '_blank' || (node.option? 'noopener')
    elsif rel
      attrs << %( rel="#{rel}")
    end
    attrs
  end

  def encode_attribute_value val
    (val.include? '"') ? (val.gsub '"', '&quot;') : val
  end

  def get_root_document node
    while (node = node.document).nested?
      node = node.parent_document
    end
    node
  end

  # NOTE adapt to older converters that relied on unprefixed method names
  def method_missing id, *args
    !((name = id.to_s).start_with? 'convert_') && (handles? name) ? (send %(convert_#{name}), *args) : super
  end

  def respond_to_missing? id, *options
    !((name = id.to_s).start_with? 'convert_') && (handles? name)
  end
end
