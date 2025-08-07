class HighlightJsAdapter < Asciidoctor::SyntaxHighlighter::Base
    register_for 'highlightjs', 'highlight.js'

    # REMIND: we cannot use Highlight.js 11+ because unescaped HTML support has been removed:
    # https://github.com/highlightjs/highlight.js/issues/2889
    # We are using unescaped HTML in source blocks for callout.
    HIGHLIGHT_JS_VERSION = '10.7.3'

    def initialize *args
      super
      @name = @pre_class = 'highlightjs'
    end

    def format node, lang, opts
      super node, lang, (opts.merge transform: proc { |pre, code|
        code['class'] = %(language-#{lang || 'none'} hljs)
        code['data-noescape'] = true
        if (id = node.attr('data-id'))
          pre['data-id'] = id
        end
        if node.option?('trim')
          code['data-trim'] = ''
        end
      })
    end

    def docinfo? location
      location == :footer
    end

    def docinfo location, doc, opts
      base_url = doc.attr 'highlightjsdir', %(#{opts[:cdn_base_url]}/highlight.js/#{HIGHLIGHT_JS_VERSION})
      %(<link rel="stylesheet" href="#{base_url}/styles/#{doc.attr 'highlightjs-theme', 'atom-one-light'}.min.css"#{opts[:self_closing_tag_slash]}>
<script src="#{base_url}/highlight.min.js"></script>
#{(doc.attr? 'highlightjs-languages') ? ((doc.attr 'highlightjs-languages').split ',').map {|lang| %[<script src="#{base_url}/languages/#{lang.lstrip}.min.js"></script>\n] }.join : ''}
<script>
hljs.highlightAll();
</script>)
    end
end