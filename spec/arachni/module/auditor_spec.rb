require_relative '../../spec_helper'
require_from_root( 'framework' )

class AuditorTest
    include Arachni::Module::Auditor
    include Arachni::UI::Output

    def initialize( framework )
        @framework = framework
        http.trainer.set_page( page )
        mute!
    end

    def page
        @page ||= Arachni::Parser::Page.new(
            url:  @framework.opts.url.to_s,
            body: 'Match this!',
            method: 'get'
        )
    end

    def http
        @framework.http
    end

    def framework
        @framework
    end

    def load_page_from( url )
        http.get( url ).on_complete {
            |res|
            @page = Arachni::Parser::Page.from_http_response( res, framework.opts )
        }
        http.run
    end

    def self.info
        {
            :name => 'Test auditor',
            :issue => {
                :name => 'Test issue'
            }
        }
    end
end

describe Arachni::Module::Auditor do

    before :all do
        @opts = Arachni::Options.instance
        @opts.audit_links = true
        @opts.audit_forms = true
        @opts.audit_cookies = true
        @opts.audit_headers = true

        @opts.url = @url = server_url_for( :auditor )

        @framework = Arachni::Framework.new( @opts )
        @auditor = AuditorTest.new( @framework )
    end

    after :each do
        @framework.modules.results.clear
        Arachni::Element::Auditable.reset
    end

    describe :register_results do
        it 'should register issues with the framework' do
            issue = Arachni::Issue.new( name: 'Test issue', url: @url )
            @auditor.register_results( [ issue ] )

            logged_issue = @framework.modules.results.first
            logged_issue.should be_true

            logged_issue.name.should == issue.name
            logged_issue.url.should  == issue.url
        end
    end

    describe :log_remote_file_if_exists do
        before do
            @base_url = @url + '/log_remote_file_if_exists/'
        end

        it 'should log issue if file exists' do
            file = @base_url + 'true'
            @auditor.log_remote_file_if_exists( file )
            @framework.http.run

            logged_issue = @framework.modules.results.first
            logged_issue.should be_true

            logged_issue.url.split( '?' ).first.should == file
            logged_issue.elem.should == Arachni::Issue::Element::PATH
            logged_issue.id.should == 'true'
            logged_issue.injected.should == 'true'
            logged_issue.mod_name.should == @auditor.class.info[:name]
            logged_issue.name.should == @auditor.class.info[:issue][:name]
            logged_issue.verification.should be_false
        end

        it 'should not log issue if file doesn\'t exist' do
            @auditor.log_remote_file_if_exists( @base_url + 'false' )
            @framework.http.run
            @framework.modules.results.should be_empty
        end
    end

    describe :remote_file_exist? do
        before do
            @base_url = @url + '/log_remote_file_if_exists/'
        end

        it 'should return true if file exists' do
            exists = false
            @auditor.remote_file_exist?( @base_url + 'true' ) {
                |bool|
                exists = bool
            }
            @framework.http.run
            exists.should be_true
        end

        it 'should return false if file doesn\'t exist' do
            exists = true
            @auditor.remote_file_exist?( @base_url + 'false' ) {
                |bool|
                exists = bool
            }
            @framework.http.run
            exists.should be_false
        end

        context 'when faced with a custom 404' do
            before { @_404_url = @base_url + 'custom_404/' }

            it 'should be able to handle it if it remains the same' do
                exists = true
                @auditor.remote_file_exist?( @_404_url + 'static/this_does_not_exist' ) {
                    |bool|
                    exists = bool
                }
                @framework.http.run
                exists.should be_false
            end

            it 'should be able to handle it if the response contains the invalid request' do
                exists = true
                @auditor.remote_file_exist?( @_404_url + 'invalid/this_does_not_exist' ) {
                    |bool|
                    exists = bool
                }
                @framework.http.run
                exists.should be_false
            end

            it 'should be able to handle it if the response contains dynamic data' do
                exists = true
                @auditor.remote_file_exist?( @_404_url + 'dynamic/this_does_not_exist' ) {
                    |bool|
                    exists = bool
                }
                @framework.http.run
                exists.should be_false
            end

            it 'should be able to handle a combination of the above with multiple requests' do
                exist = []
                500.times{
                    @auditor.remote_file_exist?( @_404_url + 'combo/this_does_not_exist_' + rand( 9999 ).to_s ) {
                        |bool|
                        exist << bool
                    }
                }
                @framework.http.run
                exist.include?( true ).should be_false
            end

        end
    end


    describe :log_remote_file do
        it 'should log a remote file' do
            file = @url + '/log_remote_file_if_exists/true'
            @framework.http.get( file ).on_complete {
                |res|
                @auditor.log_remote_file( res )
            }
            @framework.http.run

            logged_issue = @framework.modules.results.first
            logged_issue.should be_true

            logged_issue.url.split( '?' ).first.should == file
            logged_issue.elem.should == Arachni::Issue::Element::PATH
            logged_issue.id.should == 'true'
            logged_issue.injected.should == 'true'
            logged_issue.mod_name.should == @auditor.class.info[:name]
            logged_issue.name.should == @auditor.class.info[:issue][:name]
            logged_issue.verification.should be_false
        end
    end

    describe :log_issue do
        it 'should log an issue' do
            opts = { name: 'Test issue', url: @url }
            @auditor.log_issue( opts )

            logged_issue = @framework.modules.results.first
            logged_issue.name.should == opts[:name]
            logged_issue.url.should  == opts[:url]
        end
    end

    describe :match_and_log do

        before do
            @base_url = @url + '/match_and_log'
            @regex = {
                :valid   => /match/i,
                :invalid => /will not match/,
            }
        end

        context 'when given a response' do
            after do
                @framework.http.run
            end

            it 'should log issue if pattern matches' do
                @framework.http.get( @base_url ).on_complete {
                    |res|

                    regexp = @regex[:valid]

                    @auditor.match_and_log( regexp, res.body )

                    logged_issue = @framework.modules.results.first
                    logged_issue.should be_true

                    logged_issue.url.should == @opts.url.to_s
                    logged_issue.elem.should == Arachni::Issue::Element::BODY
                    logged_issue.opts[:regexp].should == regexp.to_s
                    logged_issue.opts[:match].should == 'Match'
                    logged_issue.opts[:element].should == Arachni::Issue::Element::BODY
                    logged_issue.regexp.should == regexp.to_s
                    logged_issue.verification.should be_false
                }
            end

            it 'should not log issue if pattern doesn\'t match' do
                @framework.http.get( @base_url ).on_complete {
                    |res|
                    @auditor.match_and_log( @regex[:invalid], res.body )
                    @framework.modules.results.should be_empty
                }
            end
        end

        context 'when defaulting to current page' do
            it 'should log issue if pattern matches' do
                regexp = @regex[:valid]

                @auditor.match_and_log( regexp )

                logged_issue = @framework.modules.results.first
                logged_issue.should be_true

                logged_issue.url.should == @opts.url.to_s
                logged_issue.elem.should == Arachni::Issue::Element::BODY
                logged_issue.opts[:regexp].should == regexp.to_s
                logged_issue.opts[:match].should == 'Match'
                logged_issue.opts[:element].should == Arachni::Issue::Element::BODY
                logged_issue.regexp.should == regexp.to_s
                logged_issue.verification.should be_false
            end

            it 'should not log issue if pattern doesn\'t match ' do
                @auditor.match_and_log( @regex[:invalid] )
                @framework.modules.results.should be_empty
            end
        end
    end

    describe :log do

        before do
            @log_opts = {
                altered:  'foo',
                injected: 'foo injected',
                id: 'foo id',
                regexp: /foo regexp/,
                match: 'foo regexp match',
                element: Arachni::Issue::Element::LINK
            }
        end


        context 'when given a response' do

            after { @framework.http.run }

            it 'populates and logs an issue with response data' do
                @framework.http.get( @opts.url.to_s ).on_complete {
                    |res|

                    @auditor.log( @log_opts, res )

                    logged_issue = @framework.modules.results.first
                    logged_issue.should be_true

                    logged_issue.url.should == res.effective_url
                    logged_issue.elem.should == Arachni::Issue::Element::LINK
                    logged_issue.opts[:regexp].should == @log_opts[:regexp].to_s
                    logged_issue.opts[:match].should == @log_opts[:match]
                    logged_issue.opts[:element].should == Arachni::Issue::Element::LINK
                    logged_issue.regexp.should == @log_opts[:regexp].to_s
                    logged_issue.verification.should be_false
                }
            end
        end

        context 'when it defaults to current page' do
            it 'populates and logs an issue with page data' do
                @auditor.log( @log_opts )

                logged_issue = @framework.modules.results.first
                logged_issue.should be_true

                logged_issue.url.should == @auditor.page.url
                logged_issue.elem.should == Arachni::Issue::Element::LINK
                logged_issue.opts[:regexp].should == @log_opts[:regexp].to_s
                logged_issue.opts[:match].should == @log_opts[:match]
                logged_issue.opts[:element].should == Arachni::Issue::Element::LINK
                logged_issue.regexp.should == @log_opts[:regexp].to_s
                logged_issue.verification.should be_false
            end
        end

    end

    describe :audit do

        before do
            @seed = 'my_seed'
            @default_input_value = 'blah'
         end

        context 'when called with no opts' do
            it 'should use the defaults' do
                @auditor.load_page_from( @url + '/link' )
                @auditor.audit( @seed )
                @framework.http.run
                @framework.modules.results.size.should == 4
            end
        end

        context 'when called with option' do

            describe :format do

                before { @auditor.load_page_from( @url + '/link' ) }

                describe 'Arachni::Module::Auditor::Format::STRAIGHT' do
                    it 'should inject the seed as is' do
                        @auditor.audit( @seed,
                            format: [ Arachni::Module::Auditor::Format::STRAIGHT ] )
                        @framework.http.run
                        @framework.modules.results.size.should == 1
                        @framework.modules.results.first.injected.should == @seed
                    end
                end

                describe 'Arachni::Module::Auditor::Format::APPEND' do
                    it 'should append the seed to the existing value of the input' do
                        @auditor.audit( @seed,
                            format: [ Arachni::Module::Auditor::Format::APPEND ] )
                        @framework.http.run
                        @framework.modules.results.size.should == 1
                        @framework.modules.results.first.injected.should == @default_input_value + @seed
                    end
                end

                describe 'Arachni::Module::Auditor::Format::NULL' do
                    it 'should terminate the seed with a null character' do
                        @auditor.audit( @seed,
                            format: [ Arachni::Module::Auditor::Format::NULL ] )
                        @framework.http.run
                        @framework.modules.results.size.should == 1
                        @framework.modules.results.first.injected.should == @seed + "\0"
                    end
                end

                describe 'Arachni::Module::Auditor::Format::SEMICOLON' do
                    it 'should prepend the seed with a semicolon' do
                        @auditor.audit( @seed,
                            format: [ Arachni::Module::Auditor::Format::SEMICOLON ] )
                        @framework.http.run
                        @framework.modules.results.size.should == 1
                        @framework.modules.results.first.injected.should == ';' + @seed
                    end
                end
            end

            describe :elements do

                before { @auditor.load_page_from( @url + '/elem_combo' ) }

                describe 'Arachni::Module::Auditor::Element::LINK' do
                    it 'should audit links' do
                        @auditor.audit( @seed,
                            format: [ Arachni::Module::Auditor::Format::STRAIGHT ],
                            elements: [ Arachni::Module::Auditor::Element::LINK ]
                         )
                        @framework.http.run
                        @framework.modules.results.size.should == 1
                        issue = @framework.modules.results.first
                        issue.elem.should == Arachni::Module::Auditor::Element::LINK
                        issue.var.should == 'link_input'
                    end
                end
                describe 'Arachni::Module::Auditor::Element::FORM' do
                    it 'should audit forms' do
                        @auditor.audit( @seed,
                            format: [ Arachni::Module::Auditor::Format::STRAIGHT ],
                            elements: [ Arachni::Module::Auditor::Element::FORM ]
                         )
                        @framework.http.run
                        @framework.modules.results.size.should == 1
                        issue = @framework.modules.results.first
                        issue.elem.should == Arachni::Module::Auditor::Element::FORM
                        issue.var.should == 'form_input'
                    end
                end
                describe 'Arachni::Module::Auditor::Element::COOKIE' do
                    it 'should audit cookies' do
                        @auditor.audit( @seed,
                            format: [ Arachni::Module::Auditor::Format::STRAIGHT ],
                            elements: [ Arachni::Module::Auditor::Element::COOKIE ]
                         )
                        @framework.http.run
                        @framework.modules.results.size.should == 1
                        issue = @framework.modules.results.first
                        issue.elem.should == Arachni::Module::Auditor::Element::COOKIE
                        issue.var.should == 'cookie_input'
                    end
                end
                describe 'Arachni::Module::Auditor::Element::HEADER' do
                    it 'should audit headers' do
                        @auditor.audit( @seed,
                            format: [ Arachni::Module::Auditor::Format::STRAIGHT ],
                            elements: [ Arachni::Module::Auditor::Element::HEADER ]
                         )
                        @framework.http.run
                        @framework.modules.results.size.should == 1
                        issue = @framework.modules.results.first
                        issue.elem.should == Arachni::Module::Auditor::Element::HEADER
                        issue.var.should == 'referer'
                    end
                end

                context 'when using default options' do
                    it 'should audit all element types' do
                        @auditor.audit( @seed,
                            format: [ Arachni::Module::Auditor::Format::STRAIGHT ]
                         )
                        @framework.http.run
                        @framework.modules.results.size.should == 4
                    end
                end
            end

            context 'for matching with' do
                before { @auditor.load_page_from( @url + '/link' ) }

                describe :regexp do
                    context 'with valid :match' do
                        it 'should verify the matched data with the provided string' do
                            @auditor.audit( @seed,
                                regexp: /my_.+d/,
                                match: @seed,
                                format: [ Arachni::Module::Auditor::Format::STRAIGHT ]
                             )
                            @framework.http.run
                            @framework.modules.results.size.should == 1
                            @framework.modules.results.first.injected.should == @seed
                        end
                    end

                    context 'with invalid :match' do
                        it 'should not log issue' do
                            @auditor.audit( @seed,
                                regexp: @seed,
                                match: 'blah',
                                format: [ Arachni::Module::Auditor::Format::STRAIGHT ]
                             )
                            @framework.http.run
                            @framework.modules.results.should be_empty
                        end
                    end

                    context 'without :match' do
                        it 'should try to match the provided pattern' do
                            @auditor.audit( @seed,
                                regexp: @seed,
                                format: [ Arachni::Module::Auditor::Format::STRAIGHT ]
                             )
                            @framework.http.run
                            @framework.modules.results.size.should == 1
                            @framework.modules.results.first.injected.should == @seed
                        end
                    end
                end

                describe :substring do
                    it 'should try to find the provided substring' do
                        @auditor.audit( @seed,
                            substring: @seed,
                            format: [ Arachni::Module::Auditor::Format::STRAIGHT ]
                         )
                        @framework.http.run
                        @framework.modules.results.size.should == 1
                    end
                end
            end

            describe :train do
                context 'default' do
                    it 'should parse the responses of forms submitted with their default values and feed any new elements back to the framework to be audited' do
                        # flush any exisiting pages from the buffer
                        @framework.http.trainer.flush_pages

                        page = nil
                        @framework.http.get( @url + '/train/default' ).on_complete {
                            |res|
                            page = Arachni::Parser::Page.from_http_response( res, @opts )
                        }
                        @framework.http.run

                        # page feedback queue
                        pages = [ page ]
                        # audit until no more new elements appear
                        while page = pages.pop
                            auditor = Arachni::Module::Base.new( page )
                            auditor.audit( @seed )
                            # run audit requests
                            @framework.http.run
                            # feed the new pages/elements back to the queue
                            pages |= @framework.http.trainer.flush_pages
                        end

                        issue = @framework.modules.results.first
                        issue.should be_true
                        issue.elem.should == Arachni::Module::Auditor::Element::LINK
                        issue.var.should == 'you_made_it'
                    end
                end

                context true do
                    it 'should parse all responses and feed any new elements back to the framework to be audited' do
                        # flush any exisiting pages from the buffer
                        @framework.http.trainer.flush_pages

                        page = nil
                        @framework.http.get( @url + '/train/true' ).on_complete {
                            |res|
                            page = Arachni::Parser::Page.from_http_response( res, @opts )
                        }
                        @framework.http.run

                        # page feedback queue
                        pages = [ page ]
                        # audit until no more new elements appear
                        while page = pages.pop
                            auditor = Arachni::Module::Base.new( page )
                            auditor.audit( @seed, train: true )
                            # run audit requests
                            @framework.http.run
                            # feed the new pages/elements back to the queue
                            pages |= @framework.http.trainer.flush_pages
                        end

                        issue = @framework.modules.results.first
                        issue.should be_true
                        issue.elem.should == Arachni::Module::Auditor::Element::FORM
                        issue.var.should == 'you_made_it'
                    end
                end

                context false do
                    it 'should skip analysis' do
                        # flush any exisiting pages from the buffer
                        @framework.http.trainer.flush_pages

                        page = nil
                        @framework.http.get( @url + '/train/true' ).on_complete {
                            |res|
                            page = Arachni::Parser::Page.from_http_response( res, @opts )
                        }
                        @framework.http.run

                        auditor = Arachni::Module::Base.new( page )
                        auditor.audit( @seed, train: false )
                        @framework.http.run
                        @framework.http.trainer.flush_pages.should be_empty
                    end
                end
            end

            describe :redundant do
                before do
                    @audit_opts = {
                        format: [ Arachni::Module::Auditor::Format::STRAIGHT ],
                        elements: [ Arachni::Module::Auditor::Element::LINK ]
                    }
                end

                context true do
                    it 'should allow redundant requests/audits' do
                        audits = Hash.new( 0 )
                        2.times {
                            |i|
                            @auditor.audit( @seed, @audit_opts.merge( redundant: true )){
                                audits[i] += 1
                            }
                        }
                        @framework.http.run
                        # since we've enabled redundant audits both should be performed
                        # the same amount of times (2)
                        audits.values.first.should == audits.values.last
                        audits.values.first.should == 2
                        audits.size.should == 2
                    end
                end

                context false do
                    it 'should not allow redundant requests/audits' do
                        audits = Hash.new( 0 )
                        2.times {
                            |i|
                            @auditor.audit( @seed, @audit_opts.merge( redundant: false )){
                                audits[i] += 1
                            }
                        }
                        @framework.http.run
                        # since we've disabled redundant audits only the first
                        # one should be performed
                        audits.size.should == 1
                    end
                end

                context 'default' do
                    it 'should not allow redundant requests/audits' do
                        audits = Hash.new( 0 )
                        2.times {
                            |i|
                            @auditor.audit( @seed, @audit_opts ) {
                                audits[i] += 1
                            }
                        }
                        @framework.http.run
                        audits.size.should == 1
                    end
                end
            end

            describe :async do
                before do
                    # will sleep 2 secs before each response
                    @auditor.load_page_from( @url + '/sleep' )
                end

                context true do
                    it 'should perform all HTTP requests asynchronously' do
                        before = Time.now
                        @auditor.audit_links( @seed, async: true )
                        @framework.http.run

                        # should take as long as the longest request
                        # and since we're doing this locally the longest
                        # request must take less than a second.
                        #
                        # so it should be 2 when converted into an Int
                        (Time.now - before).to_i.should == 2

                        issue = @framework.modules.results.first
                        issue.should be_true
                        issue.elem.should == Arachni::Module::Auditor::Element::LINK
                        issue.var.should == 'input'
                    end
                end

                context false do
                    it 'should perform all HTTP requests synchronously' do
                        before = Time.now
                        @auditor.audit_links( @seed, async: false )
                        @framework.http.run

                        (Time.now - before).should > 4.0

                        issue = @framework.modules.results.first
                        issue.should be_true
                        issue.elem.should == Arachni::Module::Auditor::Element::LINK
                        issue.var.should == 'input'
                    end
                end

                context 'default' do
                    it 'should perform all HTTP requests asynchronously' do
                        before = Time.now
                        @auditor.audit_links( @seed )
                        @framework.http.run

                        (Time.now - before).to_i.should == 2

                        issue = @framework.modules.results.first
                        issue.should be_true
                        issue.elem.should == Arachni::Module::Auditor::Element::LINK
                        issue.var.should == 'input'
                    end
                end

            end

        end

        context 'when called with a block' do
            it 'should delegate analysis and logging to caller' do
                @auditor.load_page_from( @url + '/link' )
                @auditor.audit( @seed ){}
                @framework.http.run
                @framework.modules.results.should be_empty
            end
        end

    end

    describe :audit_timeout do
        before do
            @timeout_opts = {
                format: [ Arachni::Module::Auditor::Format::STRAIGHT ],
                elements: [ Arachni::Issue::Element::LINK ]
            }

            @timeout_url = @url + '/timeout/'
        end

        describe :timeout_divider do
            context 'when set' do
                it 'should modify the final timeout value' do
                    @auditor.load_page_from( @timeout_url + 'true' )
                    @auditor.audit_timeout( '__TIME__',
                        @timeout_opts.merge(
                            timeout_divider: 1000,
                            timeout: 2000
                        )
                    )
                    Arachni::Module::Auditor.timeout_audit_run

                    @framework.modules.results.should be_any
                    @framework.modules.results.first.injected.should == 4.to_s
                end
            end

            context 'when not set' do
                it 'should not modify the final timeout value' do
                    @auditor.load_page_from( @timeout_url + 'true' )
                    @auditor.audit_timeout( '__TIME__', @timeout_opts.merge( timeout: 2 ))
                    Arachni::Module::Auditor.timeout_audit_run

                    @framework.modules.results.should be_any
                    @framework.modules.results.first.injected.should == 4.to_s
                end
            end
        end

        context 'when a page has a high response time'do

            before do
                @delay_opts = {
                    timeout_divider: 1000,
                    timeout: 2000
                }.merge( @timeout_opts )
            end

            context 'but isn\'t vulnerable' do
                it 'should not log issue' do
                    @auditor.load_page_from( @timeout_url + 'false' )
                    @auditor.audit_timeout( '__TIME__', @delay_opts )
                    Arachni::Module::Auditor.timeout_audit_run
                    @framework.modules.results.should be_empty
                end
            end

            context 'and is vulnerable' do
                it 'should log issue' do
                    @auditor.load_page_from( @timeout_url + 'high_response_time' )
                    @auditor.audit_timeout( '__TIME__', @delay_opts )
                    Arachni::Module::Auditor.timeout_audit_run
                    @framework.modules.results.should be_any
                end
            end
        end

    end

end
