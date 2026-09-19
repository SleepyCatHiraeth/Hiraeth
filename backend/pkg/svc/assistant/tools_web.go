package assistant

import (
	"context"
	"encoding/json"
	"fmt"
	"html"
	"net/url"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"
)

// The research tools.
//
// Two tools, not five. A 14B model asked to choose between `wikipedia`,
// `hackernews`, `stackexchange` and `arxiv` spends its reasoning on routing and
// gets it wrong; one search that queries several sources and merges them means
// the model only has to decide WHETHER to search, which it is reliably good at.
//
// Every source here is a sanctioned, keyless API. None of them is scraped:
// DuckDuckGo, searx.be and Marginalia were all measured on 2026-09-13 and are
// either blocked, JSON-disabled or gone, and building on a page parser that
// breaks when a CSS class changes is not worth doing.
//
// Known gap: none of these covers general or commercial queries, or breaking
// news. That needs a keyed engine and is deliberately not here.

func init() {
	registerTool(Tool{
		Name: "web_search",
		Describe: "Search the web for current information. Covers encyclopedic facts (Wikipedia), " +
			"technical questions (Stack Exchange) and technology news and discussion (Hacker News). " +
			"Returns titles, sources and URLs. Use fetch_url afterwards to read any result in full.",
		Params: []ToolParam{
			{Name: "query", Kind: "string", Describe: "What to search for", Required: true},
		},
		Timeout: 20 * time.Second,
		Run:     runWebSearch,
	})

	registerTool(Tool{
		Name: "fetch_url",
		Describe: "Read the text of one web page. Use it on a URL that web_search returned, " +
			"or one the user gave you, when the summary is not enough to answer.",
		Params: []ToolParam{
			{Name: "url", Kind: "string", Describe: "The full http or https URL to read", Required: true},
		},
		Timeout: 25 * time.Second,
		Run:     runFetchURL,
	})
}

// searchHit is one result, from whichever source found it.
type searchHit struct {
	Source  string
	Title   string
	URL     string
	Snippet string
}

func runWebSearch(ctx context.Context, args map[string]any) (string, error) {
	query, _ := args["query"].(string)
	query = strings.TrimSpace(query)
	if query == "" {
		return "", fmt.Errorf("web_search needs a query")
	}

	// The sources run together: three sequential round trips would put ~3s of
	// latency in front of an answer for no reason, and a slow source must not
	// decide how long the fast ones take.
	// Fixed slots, not append-as-they-finish. Appending from goroutines made
	// the order depend on which source answered first, so the same query
	// produced a different ranking each run -- and put Stack Overflow noise
	// above the Wikipedia article that actually answered the question.
	//
	// Wikipedia leads because it is the source most likely to answer a plain
	// factual question; the technical sources follow for the questions they
	// are better at. The model reads top-down.
	sources := []struct {
		fn func(context.Context, string) []searchHit
	}{
		{searchWikipedia},
		{searchStackExchange},
		{searchHackerNews},
	}
	results := make([][]searchHit, len(sources))
	var wg sync.WaitGroup
	for i, src := range sources {
		wg.Add(1)
		go func(i int, fn func(context.Context, string) []searchHit) {
			defer wg.Done()
			results[i] = fn(ctx, query)
		}(i, src.fn)
	}
	wg.Wait()

	var hits []searchHit
	for _, r := range results {
		hits = append(hits, r...)
	}

	if len(hits) == 0 {
		// An honest empty result. Inventing an answer because the search found
		// nothing is the failure mode this whole feature exists to prevent.
		return "No results found. Say so rather than answering from memory.", nil
	}

	var b strings.Builder
	for i, h := range hits {
		fmt.Fprintf(&b, "%d. [%s] %s\n   %s\n", i+1, h.Source, h.Title, h.URL)
		if h.Snippet != "" {
			fmt.Fprintf(&b, "   %s\n", clip(h.Snippet, 300))
		}
	}
	return b.String(), nil
}

func runFetchURL(ctx context.Context, args map[string]any) (string, error) {
	raw, _ := args["url"].(string)
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return "", fmt.Errorf("fetch_url needs a url")
	}
	// A Wikipedia page read as HTML is mostly navigation: the first 6000
	// characters of the Genshin Impact article contained no version number at
	// all, because the article had not started yet. The API returns the
	// article text and nothing else.
	if api, ok := wikipediaPlainTextAPI(raw); ok {
		if text, err := wikipediaExtract(ctx, api); err == nil && text != "" {
			return clip(text, 8000), nil
		}
		// Fall through to the ordinary fetch if the API disagrees.
	}

	body, ct, err := fetchBody(ctx, raw, 25*time.Second)
	if err != nil {
		return "", err
	}
	text := body
	if strings.Contains(ct, "html") {
		text = htmlToText(body)
	}
	text = strings.TrimSpace(text)
	if text == "" {
		return "", fmt.Errorf("no readable text at %s", raw)
	}
	// A page is context, not a document store. Past a few thousand words the
	// model does worse, not better, and the turn budget is finite.
	return clip(text, 6000), nil
}

// --- sources ---------------------------------------------------------------

func searchWikipedia(ctx context.Context, query string) []searchHit {
	api := "https://en.wikipedia.org/w/api.php?action=query&list=search&format=json&srlimit=5&srsearch=" +
		url.QueryEscape(query)
	var payload struct {
		Query struct {
			Search []struct {
				Title   string `json:"title"`
				Snippet string `json:"snippet"`
			} `json:"search"`
		} `json:"query"`
	}
	if err := getJSON(ctx, api, &payload, 10*time.Second); err != nil {
		return nil
	}
	var out []searchHit
	for _, r := range payload.Query.Search {
		out = append(out, searchHit{
			Source:  "Wikipedia",
			Title:   r.Title,
			URL:     "https://en.wikipedia.org/wiki/" + strings.ReplaceAll(r.Title, " ", "_"),
			Snippet: htmlToText(r.Snippet),
		})
	}
	// Wikipedia's full-text search ranks by term frequency, so a question
	// about a subject routinely puts a side article above the subject's own.
	// Asking for the current version of a game returned a character article
	// first, whose snippet named a 2023 update -- and that is the answer the
	// model gave. The article whose title the question is about goes first.
	sort.SliceStable(out, func(i, j int) bool {
		return titleCloseness(query, out[i].Title) > titleCloseness(query, out[j].Title)
	})
	return out
}

// titleCloseness scores how well an article title matches what was asked.
// Exact match beats "the query contains the title" beats everything else.
func titleCloseness(query, title string) int {
	q := strings.ToLower(strings.TrimSpace(query))
	t := strings.ToLower(strings.TrimSpace(title))
	switch {
	case q == t:
		return 3
	case strings.Contains(q, t):
		// "latest Genshin Impact update version" contains "Genshin Impact".
		return 2
	case strings.Contains(t, q):
		return 1
	}
	return 0
}

func searchStackExchange(ctx context.Context, query string) []searchHit {
	api := "https://api.stackexchange.com/2.3/search/advanced?order=desc&sort=relevance&pagesize=3" +
		"&site=stackoverflow&q=" + url.QueryEscape(query)
	var payload struct {
		Items []struct {
			Title string `json:"title"`
			Link  string `json:"link"`
			Score int    `json:"score"`
		} `json:"items"`
	}
	if err := getJSON(ctx, api, &payload, 10*time.Second); err != nil {
		return nil
	}
	var out []searchHit
	for _, it := range payload.Items {
		out = append(out, searchHit{
			Source:  "Stack Overflow",
			Title:   html.UnescapeString(it.Title),
			URL:     it.Link,
			Snippet: fmt.Sprintf("score %d", it.Score),
		})
	}
	return out
}

func searchHackerNews(ctx context.Context, query string) []searchHit {
	api := "https://hn.algolia.com/api/v1/search?tags=story&hitsPerPage=3&query=" + url.QueryEscape(query)
	var payload struct {
		Hits []struct {
			Title  string `json:"title"`
			URL    string `json:"url"`
			Points int    `json:"points"`
		} `json:"hits"`
	}
	if err := getJSON(ctx, api, &payload, 10*time.Second); err != nil {
		return nil
	}
	var out []searchHit
	for _, h := range payload.Hits {
		if h.Title == "" {
			continue
		}
		link := h.URL
		if link == "" {
			continue
		}
		out = append(out, searchHit{
			Source:  "Hacker News",
			Title:   h.Title,
			URL:     link,
			Snippet: fmt.Sprintf("%d points", h.Points),
		})
	}
	return out
}

// wikipediaPlainTextAPI maps an article URL to the extract API for it.
func wikipediaPlainTextAPI(raw string) (string, bool) {
	u, err := url.Parse(raw)
	if err != nil || !strings.HasSuffix(u.Hostname(), "wikipedia.org") {
		return "", false
	}
	title := strings.TrimPrefix(u.Path, "/wiki/")
	if title == "" || strings.Contains(title, "/") {
		return "", false
	}
	return "https://" + u.Hostname() + "/w/api.php?action=query&prop=extracts" +
		"&explaintext=1&redirects=1&format=json&titles=" + url.QueryEscape(title), true
}

func wikipediaExtract(ctx context.Context, api string) (string, error) {
	var payload struct {
		Query struct {
			Pages map[string]struct {
				Title   string `json:"title"`
				Extract string `json:"extract"`
			} `json:"pages"`
		} `json:"query"`
	}
	if err := getJSON(ctx, api, &payload, 15*time.Second); err != nil {
		return "", err
	}
	for _, pg := range payload.Query.Pages {
		if pg.Extract != "" {
			return pg.Title + "\n\n" + pg.Extract, nil
		}
	}
	return "", fmt.Errorf("no extract")
}

// --- helpers ---------------------------------------------------------------

func getJSON(ctx context.Context, rawurl string, dest any, timeout time.Duration) error {
	body, _, err := fetchBody(ctx, rawurl, timeout)
	if err != nil {
		return err
	}
	return json.Unmarshal([]byte(body), dest)
}

var (
	// One expression per tag pair: Go's RE2 has no backreferences, so the
	// tempting `<(script|style)...</\1>` does not compile -- and MustCompile
	// panics in init(), which would take the whole daemon down at startup.
	reScriptStyle = regexp.MustCompile(`(?is)<script[^>]*>.*?</script>|<style[^>]*>.*?</style>|<noscript[^>]*>.*?</noscript>|<svg[^>]*>.*?</svg>`)
	reTag         = regexp.MustCompile(`(?s)<[^>]+>`)
	reSpace       = regexp.MustCompile(`[ \t]+`)
	reBlankLines  = regexp.MustCompile(`\n{3,}`)
)

// htmlToText strips markup well enough to read a page.
//
// Deliberately not an HTML parser: this text goes to a language model, which
// tolerates imperfect whitespace far better than the codebase tolerates a new
// dependency. Block elements become newlines so paragraphs survive.
func htmlToText(s string) string {
	s = reScriptStyle.ReplaceAllString(s, " ")
	s = regexp.MustCompile(`(?i)</(p|div|li|tr|h[1-6]|br)>`).ReplaceAllString(s, "\n")
	s = regexp.MustCompile(`(?i)<br\s*/?>`).ReplaceAllString(s, "\n")
	s = reTag.ReplaceAllString(s, " ")
	s = html.UnescapeString(s)
	s = reSpace.ReplaceAllString(s, " ")
	s = reBlankLines.ReplaceAllString(s, "\n\n")
	return strings.TrimSpace(s)
}

func clip(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n]) + "\n[truncated]"
}
