#include "llama.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <utility>
#include <vector>

static void usage(const char * argv0) {
    std::fprintf(stderr, "usage: %s -m model.gguf [-p prompt] [-n n_predict] [-c ctx] [-i]\n", argv0);
}

static void quiet_log_callback(enum ggml_log_level level, const char * text, void * /*user_data*/) {
    if (level >= GGML_LOG_LEVEL_ERROR) {
        std::fputs(text, stderr);
    }
}

static std::string trim_newlines(std::string text) {
    while (!text.empty() && (text.back() == '\n' || text.back() == '\r')) {
        text.pop_back();
    }
    return text;
}

static std::string trim_space(std::string text) {
    while (!text.empty() && (text.front() == ' ' || text.front() == '\n' || text.front() == '\r' || text.front() == '\t')) {
        text.erase(text.begin());
    }
    while (!text.empty() && (text.back() == ' ' || text.back() == '\n' || text.back() == '\r' || text.back() == '\t')) {
        text.pop_back();
    }
    return text;
}

struct chat_turn {
    std::string role;
    std::string content;
};

static std::string strip_assistant_prefix(std::string text) {
    text = trim_space(std::move(text));

    const char * prefixes[] = {
        "Assistant:",
        "assistant:",
        "ASSISTANT:",
        "<|im_start|>assistant",
        "<|assistant|>",
    };

    for (const char * prefix : prefixes) {
        const std::string value(prefix);
        if (text.rfind(value, 0) == 0) {
            text.erase(0, value.size());
            return trim_space(std::move(text));
        }
    }

    return text;
}

static std::string build_fallback_chat_prompt(const std::vector<chat_turn> & turns, bool add_assistant) {
    std::string prompt;
    for (const chat_turn & turn : turns) {
        if (!prompt.empty()) {
            prompt += "\n";
        }

        if (turn.role == "assistant") {
            prompt += "Assistant: ";
        } else if (turn.role == "system") {
            prompt += "System: ";
        } else {
            prompt += "User: ";
        }

        prompt += turn.content;
    }

    if (add_assistant) {
        if (!prompt.empty()) {
            prompt += "\n";
        }
        prompt += "Assistant:";
    }

    return prompt;
}

static std::string build_chat_prompt(llama_model * model, const std::vector<chat_turn> & turns, bool add_assistant) {
    const char * tmpl = llama_model_chat_template(model, nullptr);
    if (tmpl == nullptr || turns.empty()) {
        return build_fallback_chat_prompt(turns, add_assistant);
    }

    std::vector<llama_chat_message> messages;
    messages.reserve(turns.size());
    for (const chat_turn & turn : turns) {
        messages.push_back({ turn.role.c_str(), turn.content.c_str() });
    }

    int32_t needed = llama_chat_apply_template(tmpl, messages.data(), messages.size(), add_assistant, nullptr, 0);
    if (needed <= 0) {
        return build_fallback_chat_prompt(turns, add_assistant);
    }

    std::string rendered(static_cast<size_t>(needed), '\0');
    const int32_t written = llama_chat_apply_template(
        tmpl,
        messages.data(),
        messages.size(),
        add_assistant,
        rendered.data(),
        static_cast<int32_t>(rendered.size()));

    if (written <= 0) {
        return build_fallback_chat_prompt(turns, add_assistant);
    }

    if (written < static_cast<int32_t>(rendered.size())) {
        rendered.resize(static_cast<size_t>(written));
    }

    return rendered;
}

static bool run_completion(
        llama_model * model,
        const std::string & prompt_text,
        int n_predict,
        int n_ctx,
        std::string * generated_text,
        bool stream_output) {
    const llama_vocab * vocab = llama_model_get_vocab(model);
    const int prompt_bytes = static_cast<int>(prompt_text.size());
    const int n_prompt = -llama_tokenize(vocab, prompt_text.c_str(), prompt_bytes, nullptr, 0, true, true);
    if (n_prompt <= 0) {
        std::fprintf(stderr, "failed to tokenize prompt\n");
        return false;
    }

    std::vector<llama_token> prompt_tokens(static_cast<size_t>(n_prompt));
    if (llama_tokenize(vocab, prompt_text.c_str(), prompt_bytes, prompt_tokens.data(), n_prompt, true, true) < 0) {
        std::fprintf(stderr, "failed to tokenize prompt\n");
        return false;
    }

    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = n_ctx;
    ctx_params.n_batch = static_cast<uint32_t>(n_prompt);
    ctx_params.n_ubatch = static_cast<uint32_t>(n_prompt);
    ctx_params.n_threads = 1;
    ctx_params.n_threads_batch = 1;
    ctx_params.no_perf = true;

    llama_context * ctx = llama_init_from_model(model, ctx_params);
    if (ctx == nullptr) {
        std::fprintf(stderr, "failed to create context\n");
        return false;
    }

    llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    sparams.no_perf = true;
    llama_sampler * sampler = llama_sampler_chain_init(sparams);
    llama_sampler_chain_add(sampler, llama_sampler_init_greedy());

    llama_batch batch = llama_batch_get_one(prompt_tokens.data(), n_prompt);
    int processed = 0;

    while (processed + batch.n_tokens < n_prompt + n_predict) {
        if (llama_decode(ctx, batch) != 0) {
            std::fprintf(stderr, "decode failed\n");
            llama_sampler_free(sampler);
            llama_free(ctx);
            return false;
        }

        processed += batch.n_tokens;

        const llama_token token = llama_sampler_sample(sampler, ctx, -1);
        if (llama_vocab_is_eog(vocab, token)) {
            break;
        }

        char piece[128];
        const int n_piece = llama_token_to_piece(vocab, token, piece, sizeof(piece), 0, true);
        if (n_piece < 0) {
            std::fprintf(stderr, "token->piece failed\n");
            llama_sampler_free(sampler);
            llama_free(ctx);
            return false;
        }

        generated_text->append(piece, static_cast<size_t>(n_piece));
        if (stream_output) {
            std::fwrite(piece, 1, static_cast<size_t>(n_piece), stdout);
            std::fflush(stdout);
        }
        batch = llama_batch_get_one(const_cast<llama_token *>(&token), 1);
    }

    llama_sampler_free(sampler);
    llama_free(ctx);
    return true;
}

static int run_interactive_chat(llama_model * model, int n_predict, int n_ctx) {
    std::vector<chat_turn> transcript;
    char line[2048];

    while (true) {
        std::fputs("you> ", stdout);
        std::fflush(stdout);

        if (std::fgets(line, sizeof(line), stdin) == nullptr) {
            std::fputc('\n', stdout);
            return 0;
        }

        std::string user_input = trim_newlines(line);
        if (user_input.empty()) {
            continue;
        }
        if (user_input == "/exit" || user_input == "exit" || user_input == "quit" || user_input == "/quit") {
            return 0;
        }

        transcript.push_back({ "user", user_input });
        const std::string prompt_text = build_chat_prompt(model, transcript, true);

        std::string reply;
        std::fputs("assistant> ", stdout);
        std::fflush(stdout);

        if (!run_completion(model, prompt_text, n_predict, n_ctx, &reply, true)) {
            return 1;
        }

        reply = strip_assistant_prefix(trim_newlines(reply));
        std::fputc('\n', stdout);
        std::fflush(stdout);

        transcript.push_back({ "assistant", reply });
    }
}

int main(int argc, char ** argv) {
    const char * model_path = nullptr;
    const char * prompt = "oi";
    int n_predict = 64;
    int n_ctx = 2048;
    bool interactive = false;

    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "-m") == 0 && i + 1 < argc) {
            model_path = argv[++i];
        } else if (std::strcmp(argv[i], "-p") == 0 && i + 1 < argc) {
            prompt = argv[++i];
        } else if (std::strcmp(argv[i], "-n") == 0 && i + 1 < argc) {
            n_predict = std::atoi(argv[++i]);
        } else if (std::strcmp(argv[i], "-c") == 0 && i + 1 < argc) {
            n_ctx = std::atoi(argv[++i]);
        } else if (std::strcmp(argv[i], "-i") == 0) {
            interactive = true;
        } else {
            usage(argv[0]);
            return 1;
        }
    }

    if (model_path == nullptr) {
        usage(argv[0]);
        return 1;
    }

    llama_log_set(quiet_log_callback, nullptr);
    ggml_backend_load_all();

    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = 0;
    model_params.use_mmap = false;
    model_params.use_mlock = false;

    llama_model * model = llama_model_load_from_file(model_path, model_params);
    if (model == nullptr) {
        std::fprintf(stderr, "failed to load model\n");
        return 1;
    }

    if (interactive) {
        const int rc = run_interactive_chat(model, n_predict, n_ctx);
        llama_model_free(model);
        return rc;
    }

    std::string generated;
    const std::string prompt_text = build_chat_prompt(model, { { "user", prompt } }, true);
    if (!run_completion(model, prompt_text, n_predict, n_ctx, &generated, true)) {
        llama_model_free(model);
        return 1;
    }

    generated = strip_assistant_prefix(trim_newlines(generated));
    std::fputc('\n', stdout);
    llama_model_free(model);
    return 0;
}
