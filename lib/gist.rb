class Gist
  attr_reader :from_redis, :content

  def initialize(gist_id)
    @from_redis = 'True'
    @content = RoughdraftApp::REDIS.get(gist_id)
    @gist_id = gist_id

    if ! @content
      @from_redis = 'False'
      @content = fetch
    else
      @content = JSON.parse(@content)
    end
  end

  def self.is_allowed(language, filename)
    return false if language.nil? || filename.match('SassMeister-input')

    return (language.match(/(Markdown|Literate CoffeeScript|Textile|Haml)/) || File.extname(filename) == '.txt')
  end

  def owner
    @content["owner"]["login"].to_s
  end

  def belongs_to?(user_login)
    return false unless user_login

    owner.downcase == user_login.downcase
  end

  def roughdraft_url
    "http://#{owner.downcase}.#{RoughdraftApp::APP_DOMAIN}/#{@gist_id}"
  end

  def id
    @gist_id
  end

  def description
    @content["description"].to_s
  end

  def description_safe
    context = {:whitelist => HTML::Pipeline::SanitizationFilter::FULL}
    pipe = HTML::Pipeline.new [HTML::Pipeline::SanitizationFilter], context

    pipe.call(@content["description"].to_s)[:output].to_s
  end

  def files
    @content["files"]
  end

  def file_content(file, content)
    @content["files"][file]["content"] = content
    @content["files"][file]["rendered"] = Roughdraft.gist_pipeline(content.to_s, @content)
  end

  def html_url
    @content["html_url"].to_s
  end

  def update(description, files, session)
    Chairman.session(session[:github_token]).gists.edit(id, description: description, files: files)
    @content = fetch
  end

  def delete(session)
    return Chairman.session(session[:github_token]).gists.delete(id)
  end

private

  def fetch
    begin
      gist = Github::Gists.new.get(@gist_id, client_id: Chairman.client_id, client_secret: Chairman.client_secret)

      gist.files.each do |file, value|
        if Gist.is_allowed value.language.to_s, value.filename.to_s
          value[:rendered] = Roughdraft.gist_pipeline(value, gist).gsub(/<pre(.*?)>\s+<code>/, '<pre\1><code>').gsub(/<\/code>\s+<\/pre>/, '</code></pre>')
        end
      end

      RoughdraftApp::REDIS.setex(@gist_id, 60, gist.to_hash.to_json.to_s)
      gist.to_hash

    rescue Github::Error::NotFound
      false
    end
  end
end