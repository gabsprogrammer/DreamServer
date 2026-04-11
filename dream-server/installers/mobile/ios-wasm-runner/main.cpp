#include "llama.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

static void usage(const char * argv0) {
    std::fprintf(stderr, "usage: %s -m model.gguf [-p prompt] [-n n_predict] [-c ctx] [-i]\n", argv0);
}

static void quiet_log_callback(enum ggml_log_level level, const char * text, void * /*user_data*/) {
    if (level >= GGML_LOG_LEVEL_WARN) {
        std::fputs(text, stderr);
    }
}

static std::string trim_newlines(std::string text) {
    while (!text.empty() && (text.back() == '\n' || text.back() == '\r')) {
        text.pop_back();
    }
    return text;
}

static std::string ensure_chat_prompt(const std::string & raw_input) {
    if (raw_input.find("Assistant:") != std::string::npos || raw_input.find("User:") != std::string::npos) {
        return raw_input;
    }
    return "User: " + raw_input + "\nAssistant:";
}

static bool run_completion(
        llama_model * model,
        const std::string & prompt_text,
        int n_predict,
        int n_ctx,
        std::string * generated_text) {
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
        batch = llama_batch_get_one(const_cast<llama_token *>(&token), 1);
    }

    llama_sampler_free(sampler);
    llama_free(ctx);
    return true;
}

static int run_interactive_chat(llama_model * model, int n_predict, int n_ctx) {
    std::string transcript;
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

        const std::string prompt_text =
            transcript.empty()
                ? ensure_chat_prompt(user_input)
                : transcript + "\nUser: " + user_input + "\nAssistant:";

        std::string reply;
        if (!run_completion(model, prompt_text, n_predict, n_ctx, &reply)) {
            return 1;
        }

        reply = trim_newlines(reply);
        std::printf("assistant> %s\n", reply.c_str());
        std::fflush(stdout);

        if (transcript.empty()) {
            transcript = "User: " + user_input + "\nAssistant: " + reply;
        } else {
            transcript += "\nUser: " + user_input + "\nAssistant: " + reply;
        }
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
    if (!run_completion(model, ensure_chat_prompt(prompt), n_predict, n_ctx, &generated)) {
        llama_model_free(model);
        return 1;
    }

    std::fputs(generated.c_str(), stdout);
    std::fputc('\n', stdout);
    llama_model_free(model);
    return 0;
}
