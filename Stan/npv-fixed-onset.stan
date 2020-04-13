//
// This Stan program defines a model for adjusting a predicted
// seroincidence by the sensitivity and specificity of the diagnostic.
// We assume that the sensitivity of the diagnostic decays with time.
//
// Learn more about model development with Stan at:
//
//    http://mc-stan.org/users/interfaces/rstan.html
//    https://github.com/stan-dev/rstan/wiki/RStan-Getting-Started
//

// We have RT-PCR data from two studies where patients eventually developed
// antibodies (IgG or IgM) to covid-19.
// 'N' is the number of rows in our input data, which has a row for each number of
// days since symptom onset. 'T_max' is the number of days that we would like to
// predict into the future. 'test_n' is the number of people who were tested
// and 'test_pos' is the number of people who tested positive. 't_symp_test' is
// the number of days since symptom onset. 'exposed_n' and 'exposed_pos' are
// numbers to estimate the attack rate of covid-19 from other papers.
data {
    int<lower=1> N;
    int<lower=1> J; // number of studies
    int<lower=1> T_max;
    int<lower=1> test_n[N];
    int<lower=0> test_pos[N];
    int<lower=0> t_symp_test[N];
    int<lower=1> study_idx[N];
    int<lower=1> exposed_n;
    int<lower=0> exposed_pos;
    real<lower=0> t_exp_symp;
}

// 't_new' is the log-time since exposure for the predicted times since exposure.
// 't' is the time since exposure for each row of the input data, with a fixed
// time from exposure to symptom onset of 5. We also find the orthogonal 't_ort'
// and 't_new_ort' which is used to find squared and cubic terms of log-time.
transformed data {
    real t[N];
    real t_mean;
    real t_sd;
    real t_ort[N];
    real t_new[T_max];
    real t_new_ort[T_max];

    for(i in 1:T_max)
        t_new[i] = log(i);

    t_mean = sum(t_new)/T_max;
    t_sd = sd(t_new);
    for(i in 1:(T_max)){
        t_new_ort[i] = (log(i)-t_mean)/t_sd;
    }

    for(i in 1:N){
        t[i] = t_symp_test[i]+t_exp_symp;
        t_ort[i] = (log(t[i])-t_mean)/t_sd;
    }
}

// the beta terms are the coefficients for the cubic polynomial for log-time.
// 'attack_rate' is the probability of infection given exposure.
parameters{
    real beta_0;
    real<lower=0> sigma;
    real beta_j[J];
    real beta_1;
    real beta_2;
    real beta_3;
    real<lower=0, upper=1> attack_rate;
}

// 'db_dt' is the first derivative of the log-time polynomial, which is restricted
// to be positive for the first 4 days since exposure.
transformed parameters{
    real<lower=0> db_dt[3];

    for(i in 1:3)
        db_dt[i] = beta_1+2*beta_2*(log(i+1)-t_mean)/t_sd+3*beta_3*((log(i+1)-t_mean)/t_sd)^2;
}

model {
    vector[N] mu;
    // for(i in 1:N){
    //     test_pos[i] ~ binomial_logit(test_n[i], beta_j[study_idx[i]]+beta_1*t_ort[i]+beta_2*t_ort[i]^2+beta_3*t_ort[i]^3);
    // }
    for(i in 1:N){
        mu[i] = beta_j[study_idx[i]]+beta_1*t_ort[i]+beta_2*t_ort[i]^2+beta_3*t_ort[i]^3;
    }
    target += binomial_lpmf(exposed_pos | exposed_n, attack_rate);
    target += binomial_logit_lpmf(test_pos | test_n, mu);
    target += normal_lpdf(beta_j | beta_0, sigma);
    target += normal_lpdf(beta_0 | 0, 1);
    // beta_j ~ normal(beta_0, sigma);
}

// 'sens' is the sensitivity of the RT-PCR over time for the predicted values.
// 'npv' is estimated using 'sens' and 'attack_rate'. We can also find the
// log-likelihood of the model for estimating the observed values, with the caveat
// that we don't know the likelihood of the estimates occurring prior to symptom
// onset.
generated quantities{
    vector<lower=0, upper=1>[T_max] sens;
    vector<lower=0, upper=1>[T_max] npv;
    vector[N] log_lik;

    for(i in 1:T_max){
        sens[i] = inv_logit(beta_0+beta_1*t_new_ort[i]+beta_2*t_new_ort[i]^2+beta_3*t_new_ort[i]^3);
    }

    for(i in 1:T_max){
        npv[i] = (1-attack_rate)/((1-sens[i])*attack_rate+(1-attack_rate));
    }

    for(i in 1:N){
        log_lik[i] = binomial_logit_lpmf(test_pos[i] | test_n[i], beta_0+beta_1*t_ort[i]+beta_2*t_ort[i]^2+beta_3*t_ort[i]^3);
    }
}
