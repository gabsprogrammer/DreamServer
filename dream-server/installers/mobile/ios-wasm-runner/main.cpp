#include "llama.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>

static void usage(const char * argv0) {
    std::fprintf(stderr, "usage: %s -m model.gguf [-p prompt] [-n n_predict] [-c ctx]\n", argv0);
}

int main(int argc, char ** argv) {
    const char * model_path = nullptr;
    const char * prompt = "User: oi\nAssistant:";
    int n_predict = 64;
    int n_ctx = 2048;

    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "-m") == 0 && i + 1 < argc) {
            model_path = argv[++i];
        } else if (std::strcmp(argv[i], "-p") == 0 && i + 1 < argc) {
            prompt = argv[++i];
        } else if (std::strcmp(argv[i], "-n") == 0 && i + 1 < argc) {
            n_predict = std::atoi(argv[++i]);
        } else if (std::strcmp(argv[i], "-c") == 0 && i + 1 < argc) {
            n_ctx = std::atoi(argv[++i]);
        } else {
            usage(argv[0]);
            return 1;
        }
    }

    if (model_path == nullptr) {
        usage(argv[0]);
        return 1;
    }

    ggml_backend_load_all();

    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = 0;

    llama_model * model = llama_model_load_from_file(model_path, model_params);
    if (model == nullptr) {
        std::fprintf(stderr, "failed to load model\n");
        return 1;
    }

    const llama_vocab * vocab = llama_model_get_vocab(model);
    const int prompt_bytes = static_cast<int>(std::strlen(prompt));
    const int n_prompt = -llama_tokenize(vocab, prompt, prompt_bytes, nullptr, 0, true, true);
    if (n_prompt <= 0) {
        std::fprintf(stderr, "failed to tokenize prompt\n");
        llama_model_free(model);
        return 1;
    }

    llama_token * prompt_tokens = static_cast<llama_token *>(std::malloc(sizeof(llama_token) * static_cast<size_t>(n_prompt)));
    if (prompt_tokens == nullptr) {
        std::fprintf(stderr, "failed to allocate prompt buffer\n");
        llama_model_free(model);
        return 1;
    }

    if (llama_tokenize(vocab, prompt, prompt_bytes, prompt_tokens, n_prompt, true, true) < 0) {
        std::fprintf(stderr, "failed to tokenize prompt\n");
        std::free(prompt_tokens);
        llama_model_free(model);
        return 1;
    }

    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = n_ctx;
    ctx_params.n_batch = n_prompt;
    ctx_params.no_perf = true;

    llama_context * ctx = llama_init_from_model(model, ctx_params);
    if (ctx == nullptr) {
        std::fprintf(stderr, "failed to create context\n");
        std::free(prompt_tokens);
        llama_model_free(model);
        return 1;
    }

    llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    sparams.no_perf = true;
    llama_sampler * sampler = llama_sampler_chain_init(sparams);
    llama_sampler_chain_add(sampler, llama_sampler_init_greedy());

    for (int i = 0; i < n_prompt; ++i) {
        char piece[128];
        const int n_piece = llama_token_to_piece(vocab, prompt_tokens[i], piece, sizeof(piece), 0, true);
        if (n_piece > 0) {
            std::fwrite(piece, 1, static_cast<size_t>(n_piece), stdout);
        }
    }
    std::fflush(stdout);

    llama_batch batch = llama_batch_get_one(prompt_tokens, n_prompt);
    int processed = 0;
    int generated = 0;

    while (processed + batch.n_tokens < n_prompt + n_predict) {
        if (llama_decode(ctx, batch) != 0) {
            std::fprintf(stderr, "decode failed\n");
            llama_sampler_free(sampler);
            llama_free(ctx);
            std::free(prompt_tokens);
            llama_model_free(model);
            return 1;
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
            std::free(prompt_tokens);
            llama_model_free(model);
            return 1;
        }

        std::fwrite(piece, 1, static_cast<size_t>(n_piece), stdout);
        std::fflush(stdout);

        batch = llama_batch_get_one(const_cast<llama_token *>(&token), 1);
        ++generated;
    }

    std::fputc('\n', stdout);
    std::fprintf(stderr, "generated=%d\n", generated);

    llama_sampler_free(sampler);
    llama_free(ctx);
    std::free(prompt_tokens);
    llama_model_free(model);
    return 0;
}
